import Foundation
import AVFoundation
import AudioToolbox

/// The only radio decoder runs on the computer. Nothing is routed to its speakers.
final class RadioDecoder {
    private var parser:AudioFileStreamID?
    private var converter:AVAudioConverter?
    private var format:AVAudioFormat?
    private let output:AVAudioFormat
    private let blockSamples:Int
    private var samples=[Int16](),stepIndex=0
    private var bootstrap=Data()
    private var failure:Error?
    private let emit:(Data)->Bool
    private(set) var sampleCount=0,peak=0
    init(format:RadioFormat = .legacy24k,emit:@escaping(Data)->Bool)throws {
        output=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:format.sampleRate,channels:1,interleaved:true)!
        blockSamples=format.samples;self.emit=emit
    }
    /// A two-byte sync can also occur inside MP3 payload. Require consecutive
    /// complete ADTS headers at their declared frame boundaries before hinting
    /// AAC; raw MP3 broadcasts need the MPEG hint even without a file header.
    static func containerHint(_ data:Data)->AudioFileTypeID {
        let b=Array(data.prefix(8192))
        func length(_ i:Int)->Int? {
            guard i+7<=b.count,b[i]==255,b[i+1]&0xf6==0xf0,
                  (b[i+2]>>2)&15<13 else {return nil}
            let count=Int(b[i+3]&3)<<11|Int(b[i+4])<<3|Int(b[i+5]>>5)
            return count>=((b[i+1]&1)==1 ? 7:9) ? count:nil
        }
        for i in 0..<max(0,b.count-7) {
            if let size=length(i),length(i+size) != nil {return kAudioFileAAC_ADTSType}
        }
        return kAudioFileMP3Type
    }
    private func open(_ data:Data)throws {
        let hint=Self.containerHint(data)
        let context=Unmanaged.passUnretained(self).toOpaque()
        let result=AudioFileStreamOpen(context,{ context,stream,property,_ in
            let decoder=Unmanaged<RadioDecoder>.fromOpaque(context).takeUnretainedValue()
            if property==kAudioFileStreamProperty_ReadyToProducePackets { decoder.configure(stream) }
        },{ context,bytes,packets,data,descriptions in
            Unmanaged<RadioDecoder>.fromOpaque(context).takeUnretainedValue().decode(bytes,packets,data,descriptions)
        },hint,&parser)
        guard result==noErr else { throw RadioFailure.message("无法创建音频解码器") }
    }
    deinit { if let parser=parser { AudioFileStreamClose(parser) } }
    func feed(_ data:Data)throws {
        if data.isEmpty { return }
        var data=data
        if parser==nil {
            bootstrap.append(data)
            // Probe a bounded prefix before selecting the container hint.
            if bootstrap.count<4096 { return }
            data=bootstrap;bootstrap=Data();try open(data)
        }
        guard let parser=parser else { throw RadioFailure.message("音频解码器未就绪") }
        for offset in stride(from:0,to:data.count,by:4096) {
            let chunk=data.subdata(in:offset..<min(data.count,offset+4096))
            let status=chunk.withUnsafeBytes { AudioFileStreamParseBytes(parser,UInt32($0.count),$0.baseAddress!,[]) }
            if let failure=failure { throw failure }
            guard status==noErr else { throw RadioFailure.message("音频格式不受支持（\(status)）") }
        }
    }
    private func configure(_ stream:AudioFileStreamID) {
        var description=AudioStreamBasicDescription(),size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream,kAudioFileStreamProperty_DataFormat,&size,&description)==noErr,
              let format=AVAudioFormat(streamDescription:&description),let converter=AVAudioConverter(from:format,to:output) else {
            failure=RadioFailure.message("音频格式不受支持");return
        }
        self.format=format;self.converter=converter
        var cookieSize:UInt32=0
        if AudioFileStreamGetPropertyInfo(stream,kAudioFileStreamProperty_MagicCookieData,&cookieSize,nil)==noErr,cookieSize>0,cookieSize<65536 {
            var cookie=Data(count:Int(cookieSize))
            let status=cookie.withUnsafeMutableBytes { AudioFileStreamGetProperty(stream,kAudioFileStreamProperty_MagicCookieData,&cookieSize,$0.baseAddress!) }
            if status==noErr { converter.magicCookie=cookie }
        }
    }
    private func decode(_ byteCount:UInt32,_ count:UInt32,_ data:UnsafeRawPointer,_ descriptions:UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard failure==nil,byteCount>0,count>0,byteCount<=262144,count<=4096,let format=format,let converter=converter else { return }
        let maximum=descriptions.map { d in (0..<Int(count)).map{Int(d[$0].mDataByteSize)}.max() ?? Int(byteCount) } ?? Int(byteCount/count)
        // AVAudioCompressedBuffer reserves packetCapacity * maximumPacketSize,
        // even when the actual packets are smaller. Bound that padded allocation
        // as well as the incoming payload before allocating for an Internet stream.
        guard maximum>0,maximum<=2*1024*1024/Int(count) else {
            failure=RadioFailure.message("音频数据包超出处理范围");return
        }
        let input=AVAudioCompressedBuffer(format:format,packetCapacity:count,maximumPacketSize:max(1,maximum))
        input.packetCount=count
        if let source=descriptions,let target=input.packetDescriptions {
            // ADTS callbacks include header gaps in byteCount. Packet capacity
            // covers compressed payload, not these gaps. Compact each checked
            // packet and rebase its offset instead of copying byteCount bytes
            // into a potentially smaller AVAudioCompressedBuffer.
            var offset=0
            for i in 0..<Int(count) {
                let packet=source[i],start=packet.mStartOffset,size=Int(packet.mDataByteSize)
                guard start>=0,start<=Int64(byteCount),size>0,size<=Int(byteCount)-Int(start) else {
                    failure=RadioFailure.message("音频数据包无效");return
                }
                memcpy(input.data.advanced(by:offset),data.advanced(by:Int(start)),size)
                target[i]=AudioStreamPacketDescription(mStartOffset:Int64(offset),mVariableFramesInPacket:packet.mVariableFramesInPacket,mDataByteSize:packet.mDataByteSize)
                offset+=size
            }
            input.byteLength=UInt32(offset)
        } else {
            guard byteCount%count==0 else { failure=RadioFailure.message("音频数据包无效");return }
            input.byteLength=byteCount;memcpy(input.data,data,Int(byteCount))
        }
        var supplied=false
        for _ in 0..<256 {
            guard let pcm=AVAudioPCMBuffer(pcmFormat:output,frameCapacity:8192) else { failure=RadioFailure.message("电脑音频内存不足");return }
            var error:NSError?
            let status=converter.convert(to:pcm,error:&error) { _,state in
                if supplied { state.pointee = .noDataNow;return nil }
                supplied=true;state.pointee = .haveData;return input
            }
            if let error=error { failure=error;return }
            if let channel=pcm.int16ChannelData {
                for i in 0..<Int(pcm.frameLength) {
                    let sample=channel[0][i];samples.append(sample);sampleCount+=1;peak=max(peak,abs(Int(sample)))
                    if samples.count==blockSamples {
                        let block=Self.encode(samples,index:&stepIndex);samples.removeAll(keepingCapacity:true)
                        if !emit(block) { failure=CancellationError();return }
                    }
                }
            }
            if status == .error { failure=RadioFailure.message("音频解码失败");return }
            if status != .haveData { return }
        }
        failure=RadioFailure.message("音频解码超出处理范围")
    }
    static func encode(_ samples:[Int16],index:inout Int)->Data {
        precondition(samples.count==1600 || samples.count==2400)
        var predictor=Int(samples[0]),bytes=[UInt8](repeating:0,count:4+samples.count/2)
        bytes[0]=UInt8(truncatingIfNeeded:predictor);bytes[1]=UInt8(truncatingIfNeeded:predictor>>8);bytes[2]=UInt8(index)
        for n in 1..<samples.count {
            var difference=Int(samples[n])-predictor,code=0
            if difference<0 { code=8;difference = -difference }
            let step=VoiceCodec.steps[index];var delta=step>>3
            if difference>=step { code|=4;difference-=step;delta+=step }
            if difference>=step>>1 { code|=2;difference-=step>>1;delta+=step>>1 }
            if difference>=step>>2 { code|=1;delta+=step>>2 }
            predictor=max(-32768,min(32767,predictor+(code&8 != 0 ? -delta:delta)))
            index=max(0,min(88,index+VoiceCodec.changes[code]))
            bytes[4+(n-1)/2] |= UInt8(code)<<((n-1)%2*4)
        }
        return Data(bytes)
    }
}

struct RadioPlaylist {
    var next:URL?,segments:[(Int64,URL)]=[],ended=false,sequence:Int64=0
    init(_ data:Data,base:URL)throws {
        guard data.count<=32768,let text=String(data:data,encoding:.utf8) else { throw RadioFailure.message("电台播放列表过大或格式无效") }
        let lines=text.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        if lines.contains(where:{($0.hasPrefix("#EXT-X-KEY:") && $0 != "#EXT-X-KEY:METHOD=NONE") || $0.hasPrefix("#EXT-X-MAP:") || $0.hasPrefix("#EXT-X-BYTERANGE:")}) { throw RadioFailure.message("电台分片格式不受支持") }
        let isHLS=lines.contains{$0.hasPrefix("#EXT-X-")}
        if let line=lines.first(where:{$0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:")}) { sequence=Int64(line.dropFirst(22)) ?? 0 }
        ended=lines.contains("#EXT-X-ENDLIST")
        if lines.contains(where:{$0.hasPrefix("#EXT-X-STREAM-INF:")}) {
            var best=Int.max
            for (i,line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") && i+1<lines.count {
                let lower=line.lowercased()
                guard !lower.contains("resolution="),!lower.contains("avc"),!lower.contains("hvc"),!lower.contains("hev"),!lower.contains("vp09"),!lower.contains("av01"),!lower.contains("codecs=") || lower.contains("mp4a") || lower.contains("mp3") else { continue }
                let bandwidth=Int(line.components(separatedBy:"BANDWIDTH=").dropFirst().first?.prefix(while:{$0.isNumber}) ?? "") ?? 0
                if bandwidth>0,bandwidth<=384000,bandwidth<best { next=URL(string:lines[i+1],relativeTo:base)?.absoluteURL;best=bandwidth }
            }
        } else if isHLS {
            for line in lines where !line.isEmpty && !line.hasPrefix("#") {
                guard let url=URL(string:line,relativeTo:base)?.absoluteURL else { continue };segments.append((sequence+Int64(segments.count),url))
            }
            guard segments.count<=256 else { throw RadioFailure.message("电台分片列表过大") }
        } else {
            let path=lines.first(where:{$0.lowercased().hasPrefix("file1=")}).map{String($0.dropFirst(6))} ?? lines.first(where:{!$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("[")})
            next=path.flatMap{URL(string:$0,relativeTo:base)?.absoluteURL}
        }
        if next==nil && segments.isEmpty { throw RadioFailure.message("电台播放列表中没有音频") }
    }
}

/// Stateful MPEG-TS audio extraction; continuity and PES boundaries cross segments.
struct RadioTransport {
    private var pending=Data(),pid:Int?,continuity:Int?
    mutating func audio(_ data:Data)throws->Data {
        pending.append(data);var result=Data(),consumed=0
        while pending.count-consumed>=188 {
            let b=Array(pending[consumed..<consumed+188]);consumed+=188
            guard b[0]==0x47,b[1]&0x80==0,b[3]&0xc0==0 else { throw RadioFailure.message("电台分片损坏") }
            let packetPID=Int(b[1]&31)<<8|Int(b[2]),mode=(b[3]>>4)&3
            if mode==0 || mode==2 { continue }
            var start=4
            if mode==3 { start+=1+Int(b[4]) }
            guard start<188 else { continue }
            if b[1]&0x40 != 0 {
                guard start+9<=188,b[start]==0,b[start+1]==0,b[start+2]==1,(0xc0...0xdf).contains(b[start+3]) else { continue }
                if pid==nil { pid=packetPID }
                start+=9+Int(b[start+8])
            }
            if packetPID==pid {
                let cc=Int(b[3]&15)
                if continuity==cc { continue }
                if let previous=continuity,cc != (previous+1)%16 { throw RadioFailure.message("电台分片不连续") }
                continuity=cc
                if start<188 { result.append(contentsOf:b[start..<188]) }
            }
        }
        pending=Data(pending.dropFirst(consumed));return result
    }
}

final class RadioPlayback {
    let session:String
    private let condition=NSCondition()
    private var frames=[Data](),stopped=false,completed=false
    private(set) var error:String?
    private var task:Task<Void,Never>?
    private let network:URLSession
    private let onReady:()->Void
    init(session:String,url:URL,format:RadioFormat = .legacy24k,onReady:@escaping()->Void={}) {
        self.onReady=onReady
        self.session=session
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=12;configuration.timeoutIntervalForResource=86400
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        network=URLSession(configuration:configuration)
        task=Task.detached(priority:.utility) { [self] in
            defer { finish() }
            do {
                let decoder=try RadioDecoder(format:format) { [weak self] in self?.append($0) ?? false }
                try await stream(RadioStation.resolvedStreamURL(url),decoder:decoder,depth:0)
                try Task.checkCancellation()
                throw RadioFailure.message("电台已停止发送音频")
            } catch {
                setFailure(error)
            }
        }
    }
    private func finish() {
        // This worker alone creates network tasks. Invalidating from stop()
        // races its first request (or the next HLS fetch) and raises an
        // Objective-C exception that Swift cannot catch. Cancellation wakes
        // async requests; invalidate only after the worker has left them.
        network.invalidateAndCancel()
        condition.lock();completed=true;condition.broadcast();condition.unlock()
    }
    var finished:Bool { condition.lock();defer{condition.unlock()};return completed }
    private func setFailure(_ error:Error) {
        condition.lock();if !stopped { self.error=error.localizedDescription };condition.unlock();onReady()
    }
    func stop() {
        condition.lock();stopped=true;frames=[];condition.broadcast();condition.unlock()
        task?.cancel()
    }
    func take()->Data? {
        condition.lock();defer{condition.unlock()}
        guard !frames.isEmpty else { return nil };let frame=frames.removeFirst();condition.signal();return frame
    }
    var queued:Int { condition.lock();defer{condition.unlock()};return frames.count }
    func failure()->String? { condition.lock();defer{condition.unlock()};return frames.isEmpty ? error:nil }
    private func append(_ data:Data)->Bool {
        condition.lock()
        while frames.count>=30 && !stopped { condition.wait() }
        if stopped { condition.unlock();return false }
        frames.append(data);condition.unlock();onReady();return true
    }
    private func request(_ url:URL)throws->URLRequest {
        guard ["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil,url.user==nil,url.password==nil else { throw RadioFailure.message("电台地址无效") }
        var request=URLRequest(url:url);request.setValue(AppMetadata.userAgent,forHTTPHeaderField:"User-Agent");request.setValue("0",forHTTPHeaderField:"Icy-MetaData");request.setValue("identity",forHTTPHeaderField:"Accept-Encoding");return request
    }
    private func response(_ url:URL)async throws->(URLSession.AsyncBytes,HTTPURLResponse) {
        try Task.checkCancellation()
        let (bytes,response)=try await network.bytes(for:request(url))
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),["http","https"].contains(http.url?.scheme?.lowercased() ?? "") else { throw RadioFailure.message("电台服务器连接失败") }
        return (bytes,http)
    }
    private func fetch(_ url:URL,limit:Int)async throws->(Data,URL) {
        let (bytes,http)=try await response(url);var data=Data()
        for try await byte in bytes { try Task.checkCancellation();guard data.count<limit else { throw RadioFailure.message("电台数据超出范围") };data.append(byte) }
        return (data,http.url ?? url)
    }
    private func stream(_ url:URL,decoder:RadioDecoder,depth:Int)async throws {
        guard depth<5 else { throw RadioFailure.message("电台跳转层级过多") }
        let (bytes,http)=try await response(url)
        var iterator=bytes.makeAsyncIterator(),initial=Data()
        while initial.count<512,let byte=try await iterator.next() { initial.append(byte) }
        let text=String(decoding:initial,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#extm3u") || text.hasPrefix("[playlist]") {
            var data=initial
            while let byte=try await iterator.next() { guard data.count<32768 else { throw RadioFailure.message("电台播放列表过大") };data.append(byte) }
            let base=http.url ?? url,playlist=try RadioPlaylist(data,base:base)
            if let next=playlist.next { try await stream(next,decoder:decoder,depth:depth+1);return }
            var current=playlist,last:Int64?,transport=RadioTransport(),idle=Date()
            while true {
                let candidates=last==nil && !current.ended ? Array(current.segments.suffix(2)):current.segments
                let fresh=candidates.filter{last==nil || $0.0>last!}
                for (sequence,segment) in fresh {
                    let (data,_)=try await fetch(segment,limit:2*1024*1024)
                    let audio:Data
                    if data.first==0x47 { audio=try transport.audio(data) } else { audio=data }
                    if !audio.isEmpty { try decoder.feed(audio) }
                    last=sequence;idle=Date()
                }
                if current.ended { return }
                if Date().timeIntervalSince(idle)>15 { throw RadioFailure.message("电台播放列表没有更新") }
                try await Task.sleep(nanoseconds:500_000_000)
                let (next,base)=try await fetch(base,limit:32768);current=try RadioPlaylist(next,base:base)
            }
        }
        if text.hasPrefix("<html") || text.hasPrefix("<!doctype") { throw RadioFailure.message("电台地址返回了网页") }
        // Some ICY servers ignore Icy-MetaData: 0. Strip metadata before decoding.
        let interval=Int(http.value(forHTTPHeaderField:"icy-metaint") ?? "") ?? 0
        var audioLeft=interval,metadataLeft=0,needLength=false,chunk=Data()
        func consume(_ byte:UInt8)throws {
            if interval>0 {
                if needLength { metadataLeft=Int(byte)*16;needLength=false;if metadataLeft==0 { audioLeft=interval };return }
                if metadataLeft>0 { metadataLeft-=1;if metadataLeft==0 { audioLeft=interval };return }
                audioLeft-=1;if audioLeft==0 { needLength=true }
            }
            chunk.append(byte)
            if chunk.count>=4096 { try decoder.feed(chunk);chunk.removeAll(keepingCapacity:true) }
        }
        for byte in initial { try consume(byte) }
        while let byte=try await iterator.next() { try Task.checkCancellation();try consume(byte) }
        if !chunk.isEmpty { try decoder.feed(chunk) }
    }
}
