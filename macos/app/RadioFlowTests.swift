import Foundation
enum RadioFlowTests {
 static func run(_ check:(Bool,String)->Void) {
  for allowBLE in [false,true] {
  var delivery=RadioDelivery(session:"0123456789abcdef",window:6)!,pending=Set<UInt32>(),next:UInt32=0,wifi=UInt32.max,ble=UInt32.max,played=0,underruns=0
  var seeded:UInt64=7741,started=false,lastAck = -1.0,lastPlay = -1.0
  let block=Data(repeating:0,count:1204)
  func loss(_ percent:UInt64)->Bool {seeded=seeded&*6364136223846793005&+1;return (seeded>>32)%100<percent}
  for tick in 0..<6000 {
   let now=Double(tick)*0.02
   while delivery.hasCredit {_=delivery.append(block)}
   for (packet,viaBLE) in delivery.packets(now:now,wifi:true,ble:allowBLE,primaryBLE:false) {
    if loss(viaBLE ? 0:30){continue}
    let bytes=Array(packet),sequence=(0..<4).reduce(UInt32(0)){$0|UInt32(bytes[9+$1])<<($1*8)}
    if viaBLE{ble=sequence}else{wifi=sequence}
    if sequence>=next,sequence-next<6{pending.insert(sequence)}
   }
   if !started,(0..<4).allSatisfy({pending.contains(next+UInt32($0))}){started=true;lastPlay=now-0.1}
   var pop=false
   if started,now-lastPlay>=0.099 {
    if pending.remove(next) != nil {next+=1;played+=1;lastPlay=now;pop=true}
    else{started=false;underruns+=1}
   }
   if pop || now-lastAck>=0.199 {
    lastAck=now;var mask=0
    for offset in 0..<6 where pending.contains(next+UInt32(offset)){mask|=1<<offset}
    if !loss(10){delivery.accept(["session":delivery.session,"next":next,"mask":mask,"wifi":wifi,"ble":ble,"rssi":-65])}
   }
  }
  check(played>=1175 && (!allowBLE || underruns==0),"120-second radio flow under 30% Wi-Fi loss and 10% ACK loss")
  print("Radio loss simulation BLE=\(allowBLE) fps=\(Double(played)/120) underruns=\(underruns)")
  }
  // Both links remain advertised and control replies still arrive. A one-way
  // media failure must be detected from delivery progress, not disconnection.
  for format in RadioFormat.allCases { for failingBLE in [false,true] {
   let window=format.maximumWindow,prefill=format == .legacy24k ? 8:12
   var delivery=RadioDelivery(session:"0123456789abcdef",window:window,format:format)!,pending=Set<UInt32>(),next:UInt32=0
   var started=false,lastPlay = -1.0,lastAck = -1.0,played=0,underruns=0,alternateAfterFailure=0
   var arrivals=[(Double,UInt32)]()
   let block=Data(repeating:0,count:format.blockBytes)
   for tick in 0..<3000 {
    let elapsed=Double(tick)*0.02,now=1794832623+elapsed
    while delivery.hasCredit {_=delivery.append(block)}
    for (packet,viaBLE) in delivery.packets(now:now,wifi:true,ble:true,primaryBLE:failingBLE) {
     if elapsed>=20 && viaBLE==failingBLE {continue}
     if elapsed>=20 {alternateAfterFailure+=1}
     let bytes=Array(packet),sequence=(0..<4).reduce(UInt32(0)){$0|UInt32(bytes[9+$1])<<($1*8)}
     arrivals.append((elapsed+(viaBLE ? (format == .buffered16k ? 0.35:0.2):0.02),sequence))
    }
    for (at,sequence) in arrivals where at<=elapsed {if sequence>=next && sequence-next<UInt32(window) {pending.insert(sequence)}}
    arrivals.removeAll{$0.0<=elapsed}
    if !started && (0..<prefill).allSatisfy({pending.contains(next+UInt32($0))}) {started=true;lastPlay=elapsed-0.1}
    var pop=false
    if started && elapsed-lastPlay>=0.099 {
     if pending.remove(next) != nil {next+=1;played+=1;lastPlay=elapsed;pop=true}
     else {started=false;underruns+=1}
    }
    if pop || elapsed-lastAck>=0.199 {
     var mask=0;for offset in 0..<window where pending.contains(next+UInt32(offset)){mask|=1<<offset}
     delivery.accept(["session":delivery.session,"next":next,"mask":mask,"rssi":failingBLE ? -80:-50]);lastAck=elapsed
    }
   }
   check(played>=590 && underruns==0 && alternateAfterFailure>350,"one-way \(failingBLE ? "BLE":"Wi-Fi") media loss recovers over the other attached link")
   print("Radio one-way loss format=\(format.rawValue) BLE=\(failingBLE) played=\(played) underruns=\(underruns) alternate=\(alternateAfterFailure)")
  }}

 }
}
