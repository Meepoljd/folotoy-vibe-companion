import Foundation

/// Negotiated credit window shared by both transports. Device playback advances
/// credits; receiving a duplicate never advances or replays the audio.
struct RadioDelivery {
    struct Frame { var packet:Data,sent:TimeInterval?,routeStarted:TimeInterval?,viaBLE=false }
    let session:String,nonce:UInt64,window:UInt32
    let format:RadioFormat
    private(set) var next:UInt32=0,acknowledged:UInt32=0,mask:UInt16=0
    private(set) var frames:[UInt32:Frame]=[:]
    private(set) var preferBLE=false,retransmissions=0
    private var wifiPoor=false,routeChosen=false
    private var lastEmission:TimeInterval = -100
    private var cursor:UInt32=0,cursorAt:TimeInterval?
    private var wifiReceipt:UInt32?,bleReceipt:UInt32?
    private var wifiAdvanced=false,bleAdvanced=false,holdingRoute=false
    private var routeStableUntil:TimeInterval = -100
    init?(session:String,window:Int=4,format:RadioFormat = .legacy24k) {
        guard (4...format.maximumWindow).contains(window),session.count==16,let nonce=UInt64(session,radix:16),nonce != 0 else { return nil };self.session=session;self.nonce=nonce;self.window=UInt32(window);self.format=format
    }
    var hasCredit:Bool { next &- acknowledged<window }
    mutating func append(_ block:Data)->Bool {
        guard hasCredit,block.count==format.blockBytes,block[2]<=88,block[3]==0,next<UInt32.max-window else { return false }
        var packet=Data([5])
        for shift in stride(from:0,to:64,by:8) { packet.append(UInt8(truncatingIfNeeded:nonce>>shift)) }
        for shift in stride(from:0,to:32,by:8) { packet.append(UInt8(truncatingIfNeeded:next>>shift)) }
        packet.append(UInt8(format.rawValue));packet.append(block);frames[next]=Frame(packet:packet,sent:nil,routeStarted:nil);next+=1;return true
    }
    mutating func accept(_ body:[String:Any]) {
        guard body["session"] as? String==session,let raw=body["next"] as? NSNumber,let rawMask=body["mask"] as? NSNumber,
              raw.doubleValue>=Double(acknowledged),raw.doubleValue<=Double(next),raw.doubleValue.rounded()==raw.doubleValue,
              (0..<1<<window).contains(rawMask.intValue) else { return }
        if let rssi=body["rssi"] as? Int,(-127...0).contains(rssi) {
            if rssi <= -75 {wifiPoor=true}
            else if rssi >= -68 {wifiPoor=false}
        }
        // At an unchanged playback cursor, received bits can only accumulate.
        // A delayed mirror ACK must not erase newer receipt information.
        mask=raw.uint32Value==acknowledged ? mask|rawMask.uint16Value:rawMask.uint16Value
        acknowledged=raw.uint32Value
        frames=frames.filter{$0.key>=acknowledged}
        // Only advancing, in-session media receipts can renew the chosen path.
        // Discovery, an unchanged mirror ACK or an old duplicate cannot.
        for (key,isBLE) in [("wifi",false),("ble",true)] {
            guard let value=body[key] as? NSNumber,value.doubleValue>=0,
                  value.doubleValue<Double(next),value.doubleValue.rounded()==value.doubleValue else {continue}
            let sequence=value.uint32Value,previous=isBLE ? bleReceipt:wifiReceipt
            guard previous==nil || sequence>previous! else {continue}
            if isBLE {bleReceipt=sequence;bleAdvanced=true}
            else {wifiReceipt=sequence;wifiAdvanced=true}
        }

    }
    mutating func packets(now:TimeInterval,wifi:Bool,ble:Bool,primaryBLE:Bool)->[(Data,Bool)] {
        var result=[(Data,Bool)]()
        guard now-lastEmission>=0.03 else{return result}
        if cursorAt==nil || cursor != acknowledged {cursor=acknowledged;cursorAt=now}
        let stalled=now-(cursorAt ?? now)>=0.3
        if !ble {preferBLE=false}
        else if !wifi {preferBLE=true}
        else if !routeChosen {preferBLE=primaryBLE || wifiPoor}
        if !frames.isEmpty && (wifi || ble) {routeChosen=true}
        if holdingRoute && (preferBLE ? bleAdvanced:wifiAdvanced) {routeStableUntil=max(routeStableUntil,now+0.6)}
        bleAdvanced=false;wifiAdvanced=false
        let ordered=frames.keys.sorted { (frames[$0]?.sent == nil ? 0:1,$0)<(frames[$1]?.sent == nil ? 0:1,$1) }
        for sequence in ordered {
            guard var frame=frames[sequence] else { continue }
            let offset=sequence &- acknowledged
            if offset<window,mask&(1<<offset) != 0 { continue }
            // Startup fills the negotiated receiver cache before playback credit. Once
            // running, repair a Wi-Fi hole within one audio block, before the
            // small device buffer drains. New credits cannot starve unsent data.
            // After an underrun the receiver needs its full contiguous prefill,
            // not only its leading repair horizon. A stalled cursor makes every missing
            // cache slot eligible for alternate-link repair.
            // The larger receiver needs earlier repair when a 30 ms BLE
            // connection or coexistence backlog adds several fragment intervals.
            let nearHead=acknowledged==0 || offset<min(window,max(5,window/2)) || stalled
            let routeGone=frame.viaBLE ? !ble:!wifi
            let retry=routeGone ? 0:frame.viaBLE ? (wifi && nearHead ? 0.3:0.6):(acknowledged==0 ? 0.35:0.1)
            if let sent=frame.sent,now-sent<retry { continue }
            if frame.sent != nil {
                retransmissions+=1
                // Actual missing near-playhead media, not discovery or RSSI,
                // can move a running session. Try the other direction as well:
                // a connected BLE link can still lose write commands while its
                // notifications and control heartbeats remain healthy.
                if nearHead,now>=routeStableUntil,now-(frame.routeStarted ?? now)>=(frame.viaBLE ? 0.3:0.35) {
                    let previous=preferBLE
                    if frame.viaBLE && wifi {preferBLE=false}
                    else if !frame.viaBLE && ble {preferBLE=true}
                    if preferBLE != previous {holdingRoute=true;routeStableUntil=now+1}
                }
            }
            let useBLE=ble && (preferBLE || !wifi)
            guard wifi || useBLE else { continue }
            if frame.routeStarted==nil || (frame.sent != nil && frame.viaBLE != useBLE) {frame.routeStarted=now}
            frame.sent=now;frame.viaBLE=useBLE;frames[sequence]=frame;result.append((frame.packet,useBLE));lastEmission=now;break
        }
        // Retain a working media path for this listening session. Sparse
        // Wi-Fi probe receipts cannot establish sustained delivery quality;
        // returning merely because Wi-Fi reappears can create another gap.
        return result
    }
}
