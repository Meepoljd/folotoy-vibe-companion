import Foundation

enum RadioTests {
    static func run(_ check:(Bool,String)->Void) {
        RadioFlowTests.run(check)
        let legacy=URL(string:"https://rfienchinois64k.ice.infomaniak.ch//rfienchinois-64.mp3?token=kept")!
        check(RadioStation.resolvedStreamURL(legacy).absoluteString=="https://rfienchinois64k.ice.infomaniak.ch/rfienchinois-64.mp3?token=kept","legacy preset path repair preserves query and stored list")
        let other=URL(string:"https://example.com//station.mp3")!
        check(RadioStation.resolvedStreamURL(other)==other,"other providers retain their exact URL path")
        check(RadioDecoder.containerHint(Data([0xff,0xfb,0x90,0,0xff,0xf1,0,0,0,0,0,0,0]))==RadioDecoder.containerHint(Data()),"MP3 payload sync bytes cannot force the AAC parser")
        let adts: [UInt8]=[0xff,0xf1,0x4c,0x80,0x01,0x1f,0xfc,0]
        check(RadioDecoder.containerHint(Data(adts+adts)) != 0,"two ADTS frame boundaries select AAC")
        var index=0
        let silence=RadioDecoder.encode([Int16](repeating:0,count:2400),index:&index)
        check(silence==Data(repeating:0,count:1204),"radio independent IMA silence")
        var delivery=RadioDelivery(session:"0123456789abcdef")!
        for _ in 0..<4 { check(delivery.append(silence),"radio four initial credits") }
        check(!delivery.append(silence),"radio bounded producer window")
        var sent=[(Data,Bool)]()
        for n in 0..<4 {sent+=delivery.packets(now:Double(n)*0.05,wifi:true,ble:true,primaryBLE:false)}
        check(sent.count==4 && sent.allSatisfy{!$0.1} && sent[0].0.count==1218,"radio Wi-Fi initial delivery and packet size")
        check(Array(sent[0].0.prefix(14))==[5,0xef,0xcd,0xab,0x89,0x67,0x45,0x23,0x01,0,0,0,0,1],"radio fixed little-endian wire layout")
        check(delivery.packets(now:0.2,wifi:true,ble:true,primaryBLE:false).isEmpty,"radio no premature retransmission")
        var retry=[(Data,Bool)]()
        for n in 0..<4 {retry+=delivery.packets(now:0.4+Double(n)*0.05,wifi:true,ble:true,primaryBLE:false)}
        check(retry.filter{$0.1}.count==4 && delivery.preferBLE,"one-way Wi-Fi loss retries over BLE")
        delivery.accept(["session":"0123456789abcdef","next":2,"mask":2,"wifi":UInt32.max])
        check(delivery.hasCredit && delivery.frames.count==2,"playback acknowledgement releases two credits")
        let settling=delivery.packets(now:1.2,wifi:true,ble:true,primaryBLE:false)
        check(settling.allSatisfy{$0.1},"a newly selected route gets time to drain queued fragments before another switch")
        let later=delivery.packets(now:1.6,wifi:true,ble:true,primaryBLE:false)
        check(later.count==1 && !later[0].1,"a missing BLE head is repaired over Wi-Fi; received out-of-order audio is not retransmitted")
        delivery.accept(["session":"0123456789abcdef","next":0,"mask":0])
        delivery.accept(["session":"1111111111111111","next":4,"mask":0])
        delivery.accept(["session":"0123456789abcdef","next":99,"mask":0])
        check(delivery.acknowledged==2,"stale/foreign/future acknowledgements cannot corrupt credits")
        var healthy=RadioDelivery(session:"0123456789abcdef")!
        for round in 0..<3 {
            for _ in 0..<4 {_=healthy.append(silence)}
            for offset in 0..<4 {
                let packets=healthy.packets(now:Double(round)*2+Double(offset)*0.05,wifi:round>0,ble:true,primaryBLE:round==0)
                check(packets.count==1 && packets[0].1,"healthy BLE keeps sending on the same link after Wi-Fi recovery")
            }
            healthy.accept(["session":healthy.session,"next":(round+1)*4,"mask":0,"wifi":round*4+3])
        }
        check(healthy.preferBLE,"sparse Wi-Fi receipts never displace a working BLE radio session")
        _=healthy.append(silence)
        let fallback=healthy.packets(now:13,wifi:true,ble:false,primaryBLE:false)
        check(fallback.count==1 && !fallback[0].1 && !healthy.preferBLE,"BLE loss immediately makes Wi-Fi available for radio repair")
        var sticky=RadioDelivery(session:"0123456789abcdef")!;_=sticky.append(silence);_=sticky.append(silence)
        _=sticky.packets(now:0,wifi:false,ble:true,primaryBLE:true)
        check(sticky.packets(now:0.1,wifi:true,ble:true,primaryBLE:false).allSatisfy{$0.1} && sticky.preferBLE,"Wi-Fi discovery recovery cannot change a BLE-started radio route")
        var early=RadioDelivery(session:"0123456789abcdef",window:10)!
        for _ in 0..<10 {_=early.append(silence)}
        for i in 0..<10 {_=early.packets(now:Double(i)*0.05,wifi:true,ble:false,primaryBLE:false)}
        early.accept(["session":early.session,"next":4,"mask":15])
        for _ in 0..<4 {_=early.append(silence)}
        var earlyRepair=[(Data,Bool)]()
        for i in 0..<5 {earlyRepair+=early.packets(now:0.8+Double(i)*0.05,wifi:true,ble:true,primaryBLE:false)}
        check(earlyRepair.contains{$0.1},"missing audio is repaired before it reaches a 200 ms BLE transit deadline")
        var refilling=RadioDelivery(session:"0123456789abcdef",window:10)!
        for _ in 0..<10 {_=refilling.append(silence)}
        for i in 0..<10 {_=refilling.packets(now:Double(i)*0.05,wifi:false,ble:true,primaryBLE:true)}
        refilling.accept(["session":refilling.session,"next":6,"mask":15])
        for _ in 0..<6 {_=refilling.append(silence)}
        for i in 0..<6 {_=refilling.packets(now:0.5+Double(i)*0.05,wifi:false,ble:true,primaryBLE:true)}
        refilling.accept(["session":refilling.session,"next":6,"mask":63])
        var backup=[(Data,Bool)]()
        for i in 0..<40 {backup+=refilling.packets(now:1+Double(i)*0.05,wifi:true,ble:true,primaryBLE:true)}
        check(backup.contains{!$0.1},"stalled six-block prefix repairs the missing prefill tail over Wi-Fi even while BLE stays connected")
        for i in 0..<100 {
            var session=RadioDelivery(session:String(format:"%016x",i+1))!
            for sequence in 0..<100 {
                check(session.append(silence),"repeated session credit")
                _=session.packets(now:Double(sequence),wifi:sequence%2==0,ble:true,primaryBLE:sequence%2 != 0)
                session.accept(["session":session.session,"next":sequence+1,"mask":0])
            }
            check(session.frames.isEmpty && session.acknowledged==100,"repeated transport switching drains each session")
        }
        func tsPacket(_ continuity:UInt8,_ sample:UInt8)->Data {
            var bytes=[UInt8](repeating:sample,count:188)
            bytes[0]=0x47;bytes[1]=0x41;bytes[2]=1;bytes[3]=0x10|continuity
            bytes.replaceSubrange(4..<13,with:[0,0,1,0xc0,0,0,0x80,0,0]);return Data(bytes)
        }
        let transportBytes=tsPacket(0,5)+tsPacket(1,6)
        for size in [1,137,188,4096] {
            var parser=RadioTransport(),audio=Data()
            for position in stride(from:0,to:transportBytes.count,by:size) {
                audio.append(try! parser.audio(transportBytes.subdata(in:position..<min(transportBytes.count,position+size))))
            }
            check(audio==Data(repeating:5,count:175)+Data(repeating:6,count:175),"MPEG-TS cross-call Data indices and PES continuity")
        }
        var weakWiFi=RadioDelivery(session:"0123456789abcdef")!;_ = weakWiFi.append(silence)
        weakWiFi.accept(["session":weakWiFi.session,"next":0,"mask":0,"rssi":-82])
        check(weakWiFi.packets(now:0,wifi:true,ble:true,primaryBLE:false).allSatisfy{$0.1} && weakWiFi.preferBLE,"weak Wi-Fi keeps stable BLE radio and avoids duplicate probing")
        weakWiFi.accept(["session":weakWiFi.session,"next":0,"mask":0,"rssi":-72]);check(weakWiFi.preferBLE,"radio Wi-Fi quality hysteresis")
        check(weakWiFi.packets(now:1,wifi:true,ble:false,primaryBLE:false).allSatisfy{!$0.1},"Wi-Fi radio remains usable when BLE is unavailable")
        var wider=RadioDelivery(session:"0123456789abcdef",window:6)!
        for _ in 0..<6 {check(wider.append(silence),"negotiated six-frame radio window")}
        check(!wider.append(silence) && RadioDelivery(session:"0123456789abcdef",window:11)==nil,"radio window remains bounded")
        wider.accept(["session":wider.session,"next":1,"mask":31]);check(wider.acknowledged==1,"six-frame receiver mask")
        var cached=RadioDelivery(session:"0123456789abcdef",window:10)!
        for _ in 0..<10 {check(cached.append(silence),"one-second receiver cache credit")}
        check(!cached.append(silence),"ten-frame producer remains bounded")
        cached.accept(["session":cached.session,"next":0,"mask":1023])
        cached.accept(["session":cached.session,"next":0,"mask":3])
        check(cached.mask==1023 && cached.packets(now:1,wifi:true,ble:true,primaryBLE:false).isEmpty,"late mirror acknowledgement cannot erase high receipt bits")
        cached.accept(["session":cached.session,"next":1,"mask":7])
        check(cached.mask==7 && cached.hasCredit,"new cursor replaces receipt mask and releases credit")
        var attaching=RadioDelivery(session:"0123456789abcdef",window:10)!
        for _ in 0..<10 {_=attaching.append(silence)}
        for n in 0..<10 {_=attaching.packets(now:Double(n)*0.04,wifi:true,ble:false,primaryBLE:false)}
        attaching.accept(["session":attaching.session,"next":1,"mask":127])
        let repaired=attaching.packets(now:0.9,wifi:true,ble:true,primaryBLE:false)
        check(!attaching.preferBLE && repaired.allSatisfy{!$0.1},"new BLE cannot steal healthy Wi-Fi playback because of a late tail receipt")
        attaching.accept(["session":attaching.session,"next":8,"mask":0])
        check(attaching.packets(now:1.1,wifi:true,ble:true,primaryBLE:false).contains{$0.1} && attaching.preferBLE,"persistent missing playhead audio takes BLE before cache starvation")
        var longerTransit=RadioDelivery(session:"0123456789abcdef",window:16,format:.buffered16k)!
        let shortBlock=Data(repeating:0,count:804)
        for _ in 0..<16 {_=longerTransit.append(shortBlock)}
        for i in 0..<16 {_=longerTransit.packets(now:Double(i)*0.04,wifi:true,ble:false,primaryBLE:false)}
        longerTransit.accept(["session":longerTransit.session,"next":1,"mask":127])
        check(longerTransit.packets(now:0.9,wifi:true,ble:true,primaryBLE:false).contains{$0.1},"larger cache repairs its eighth pending block before slower BLE fragment delivery can starve playback")
        check(RadioFormat.supportedMask==3,"desktop advertises both wire formats")
        var buffered=RadioDelivery(session:"0123456789abcdef",window:16,format:.buffered16k)!
        var bufferedIndex=0
        let small=RadioDecoder.encode([Int16](repeating:0,count:1600),index:&bufferedIndex)
        for _ in 0..<16 {check(buffered.append(small),"sixteen buffered format credits")}
        check(!buffered.append(small) && !buffered.append(silence),"format and memory bounds are independent of credit")
        let wire=buffered.packets(now:0,wifi:false,ble:true,primaryBLE:true)
        check(wire.count==1 && wire[0].0.count==818 && wire[0].0[13]==2,"buffered format has explicit 818-byte wire framing")
        buffered.accept(["session":buffered.session,"next":0,"mask":65535])
        check(buffered.mask==UInt16.max && buffered.packets(now:1,wifi:true,ble:true,primaryBLE:false).isEmpty,"sixteenth receipt bit is retained")
        check(RadioDelivery(session:buffered.session,window:17,format:.buffered16k)==nil && RadioFormat(rawValue:3)==nil,"unsupported formats and oversized windows are rejected")
        var receiving=RadioDelivery(session:"0123456789abcdef",window:16,format:.buffered16k)!
        for _ in 0..<16 {_=receiving.append(shortBlock)}
        for n in 0..<16 {_=receiving.packets(now:Double(n)*0.04,wifi:true,ble:false,primaryBLE:false)}
        receiving.accept(["session":receiving.session,"next":1,"mask":0,"wifi":0,"ble":UInt32.max])
        _=receiving.packets(now:1,wifi:true,ble:true,primaryBLE:false)
        check(receiving.preferBLE,"missing WiFi media selects BLE")
        for n in 1...8 {
            receiving.accept(["session":receiving.session,"next":1,"mask":(1<<(n+1))-2,"ble":n+1,"wifi":0])
            _=receiving.packets(now:1+Double(n)*0.3,wifi:true,ble:true,primaryBLE:false)
            check(receiving.preferBLE,"advancing BLE media prevents a queued fragment from bouncing back to failed WiFi")
        }
        receiving.accept(["session":receiving.session,"next":1,"mask":0,"ble":1,"wifi":0])
        _=receiving.packets(now:4.2,wifi:true,ble:true,primaryBLE:false)
        check(!receiving.preferBLE,"old receipt replays do not extend a stalled route; genuine failure still falls back")
        let base=URL(string:"https://radio.example/path/list.m3u8?token=x")!
        let list=try! RadioPlaylist(Data("#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:123\n#EXTINF:2,\na.ts?key=abc\n#EXTINF:2,\nb.ts\n".utf8),base:base)
        check(list.segments.map{$0.0}==[123,124] && list.segments[0].1.absoluteString=="https://radio.example/path/a.ts?key=abc","HLS sequence and relative query resolution")
        check((try? RadioPlaylist(Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128\na.ts".utf8),base:base))==nil,"encrypted HLS is rejected explicitly")
        let master=try! RadioPlaylist(Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS=\"mp4a.40.2\"\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS=\"mp4a.40.2\"\nb.m3u8".utf8),base:base)
        check(master.next?.lastPathComponent=="b.m3u8","bounded audio-only HLS variant selection")
        let unspecified=try! RadioPlaylist(Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=256000\naudio.m3u8".utf8),base:base)
        check(unspecified.next?.lastPathComponent=="audio.m3u8","HLS without codec metadata is validated by the real decoder")
        if let i=CommandLine.arguments.firstIndex(of:"--radio-vector"),i+1<CommandLine.arguments.count {
            let expected=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[i+1]))
            let pcm=(0..<((expected.count-4)*2)).map{Int16(($0*7919)%60000-30000)};var index=0
            check(RadioDecoder.encode(pcm,index:&index)==expected,"computer encoder bit-exact with device C codec")
        }
        if let i=CommandLine.arguments.firstIndex(of:"--radio-media"),i+1<CommandLine.arguments.count {
            let files=CommandLine.arguments[(i+1)...]
            for format in RadioFormat.allCases { for path in files {
                do {
                    var blocks=0
                    let decoder=try RadioDecoder(format:format){ block in blocks+=1;return block.count==format.blockBytes }
                    let data=try Data(contentsOf:URL(fileURLWithPath:path))
                    if data.first==0x47 {var ts=RadioTransport();try decoder.feed(ts.audio(data))}
                    else { for n in stride(from:0,to:data.count,by:137) {try decoder.feed(data.subdata(in:n..<min(data.count,n+137)))} }
                    check(blocks>=5 && decoder.peak>100 && decoder.sampleCount>12000,"native decode and resample: \(URL(fileURLWithPath:path).lastPathComponent)")
                    print("Radio native decode: \(URL(fileURLWithPath:path).lastPathComponent) blocks=\(blocks) samples=\(decoder.sampleCount) peak=\(decoder.peak)")
                } catch { check(false,"native radio decode: \(error)") }
            }
        }}
        print("Radio delivery/playlist/native codec checks PASS")
    }
    static func streaming(base:URL)->Int32 {
        var failures=0
        func check(_ yes:Bool,_ label:String) { if !yes { fputs("FAIL: \(label)\n",stderr);failures+=1 } }
        for format in RadioFormat.allCases { for path in ["tone.mp3","midstream.mp3","tone.aac","list.m3u","list.pls","live.m3u8","redirect","icy"] {
            let player=RadioPlayback(session:"0123456789abcdef",url:base.appendingPathComponent(path),format:format)
            let deadline=Date().addingTimeInterval(20);var count=0
            while Date()<deadline,count<10 {
                if player.take() != nil { count+=1 }
                else if player.failure() != nil { break }
                else { Thread.sleep(forTimeInterval:0.005) }
            }
            check(count>=10,"stream decoding: \(path) \(player.failure() ?? "")")
            player.stop();let end=Date().addingTimeInterval(3)
            while !player.finished && Date()<end {Thread.sleep(forTimeInterval:0.01)}
            check(player.finished,"stream cancellation joins: \(path)")
            print("Radio stream: \(path) frames=\(count) joined=\(player.finished)")
        }
        }
        for path in ["missing","encrypted.m3u8","oversize.m3u8","html","stall.m3u8"] {
            let player=RadioPlayback(session:"0123456789abcdef",url:base.appendingPathComponent(path))
            let end=Date().addingTimeInterval(path=="stall.m3u8" ? 20:15)
            while player.failure()==nil && Date()<end { _=player.take();Thread.sleep(forTimeInterval:0.01) }
            check(player.failure() != nil,"bounded source error: \(path)");player.stop()
        }
        // Stop can run before the detached worker's first request, or during
        // an HTTP header wait. Neither may create a task on an invalid session.
        var rapid=[RadioPlayback]()
        for i in 0..<300 {
            let player=RadioPlayback(session:String(format:"%016x",i+1),url:base.appendingPathComponent("tone.mp3"),format:i%2==0 ? .legacy24k:.buffered16k)
            player.stop();rapid.append(player)
        }
        let rapidEnd=Date().addingTimeInterval(5)
        while rapid.contains(where:{!$0.finished}) && Date()<rapidEnd {Thread.sleep(forTimeInterval:0.005)}
        check(rapid.allSatisfy{$0.finished},"300 immediate stops join without invalidated-session races")
        let slow=RadioPlayback(session:"0123456789abcdef",url:base.appendingPathComponent("slow-headers"),format:.buffered16k)
        Thread.sleep(forTimeInterval:0.1);slow.stop()
        let slowEnd=Date().addingTimeInterval(3)
        while !slow.finished && Date()<slowEnd {Thread.sleep(forTimeInterval:0.005)}
        check(slow.finished,"cancelling an HTTP header wait releases the worker promptly")
        for i in 0..<20 {
            let player=RadioPlayback(session:String(format:"%016x",i+1),url:base.appendingPathComponent("tone.mp3"))
            // Let the finite decoder fill its bounded queue, then cancel while
            // producer backpressure is active. No microphone/speakers are used.
            let fillDeadline=Date().addingTimeInterval(3)
            while player.queued<30 && player.failure()==nil && Date()<fillDeadline {Thread.sleep(forTimeInterval:0.005)}
            check(player.queued==30,"producer reached its bounded backpressure queue")
            player.stop();let end=Date().addingTimeInterval(3)
            while !player.finished && Date()<end {Thread.sleep(forTimeInterval:0.005)}
            check(player.finished,"rapid radio stop releases blocked decoder")
        }
        print("Radio HTTP/HLS/ICY/errors/cancellation: \(failures==0 ? "PASS":"FAIL")")
        return failures==0 ? 0:1
    }

}
