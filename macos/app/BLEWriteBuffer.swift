import Foundation

/// Keep complete packets in order. Radio has a smaller budget so a stalled
/// media path cannot consume all control capacity. The active write is retained
/// during cancellation; the next packet's first fragment resets reassembly.
struct BLEWriteBuffer {
    private struct Part { let bytes:Data,radio:Bool,key:Data? }
    private var parts=[Part]()
    var firstIsRadio:Bool { parts.first?.radio ?? false }
    var first:Data? { parts.first?.bytes }
    var isEmpty:Bool { parts.isEmpty }
    var count:Int { parts.count }
    mutating func append(_ frames:[Data],radio:Bool,key:Data?=nil)->Bool {
        if radio,let key=key,parts.contains(where:{$0.key==key}) { return true }
        guard !frames.isEmpty,parts.count+frames.count <= (radio ? 128:256) else { return false }
        parts.append(contentsOf:frames.map{Part(bytes:$0,radio:radio,key:key)});return true
    }
    mutating func acknowledge() { if !parts.isEmpty {parts.removeFirst()} }
    mutating func reset() { parts=[] }
    mutating func acknowledgeRadio(session:UInt64,next:UInt32,mask:UInt16,writing:Bool) {
        parts=parts.enumerated().filter { index,part in
            if !part.radio || (writing && index==0) {return true}
            guard let key=part.key,key.count==13 else {return true}
            let bytes=Array(key)
            let nonce=(0..<8).reduce(UInt64(0)){$0|UInt64(bytes[1+$1])<<($1*8)}
            let sequence=(0..<4).reduce(UInt32(0)){$0|UInt32(bytes[9+$1])<<($1*8)}
            let offset=sequence &- next
            return nonce==session && offset<0x80000000 && (offset>=16 || mask&(1<<offset)==0)
        }.map{$0.element}
    }
    mutating func discardRadio(writing:Bool) {
        parts=parts.enumerated().filter{writing && $0.offset==0 || !$0.element.radio}.map{$0.element}
    }
}
