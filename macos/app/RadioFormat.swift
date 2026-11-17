import Foundation

/// Explicit wire formats let a new desktop app continue serving older devices.
/// Format 2 trades upper treble for a longer jitter buffer on the same small heap.
enum RadioFormat:Int,CaseIterable {
    case legacy24k=1,buffered16k=2
    var sampleRate:Double {self == .legacy24k ? 24000:16000}
    var samples:Int {Int(sampleRate)/10}
    var blockBytes:Int {4+samples/2}
    var maximumWindow:Int {self == .legacy24k ? 10:16}
    static let supportedMask=allCases.reduce(0){$0 | (1<<($1.rawValue-1))}
}
