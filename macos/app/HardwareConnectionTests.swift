import Foundation

// Explicit USB-authorized acceptance helper. Uses the existing credential and
// engine with no LAN socket; never pairs, fabricates approval or changes values.
enum HardwareConnectionTests {
    static func runBLE()->Int32 {
        guard let id=UserDefaults.standard.string(forKey:"device"),PairingStore.load(id) != nil else {
            print("BLE device test requires an already-authorized device");return 2
        }
        setbuf(stdout,nil)
        let engine=Engine(lanEnabled:false)
        var settingsRead=false,settingsSaved=false,radioRead=false,agentAccepted=false,startedAgent=false
        var firstConnected:Date?,lastConnected=Date.distantPast,failed=false,lastStatus=""
        engine.onState={ state in
            let status="\(state.message) | BLE: \(state.bluetoothStatus) | found=\(state.devices.count)"
            if status != lastStatus { print(status);lastStatus=status }
            if state.wifiConnected { failed=true }
            if state.connected && state.bleConnected {
                if firstConnected==nil { firstConnected=Date();print("BLE-only authenticated") }
                lastConnected=Date()
            } else if firstConnected != nil {
                firstConnected=nil;print("BLE availability window restarted")
            }
        }
        engine.onSettings={ prefs,source in
            guard source==id,!settingsRead else { return }
            settingsRead=true;print("BLE-only settings read")
            engine.save(prefs,changes:["brightness":prefs.brightness])
        }
        engine.onResult={ ok,message in
            if ok { settingsSaved=true;print("BLE-only settings acknowledged") }
            else { print("BLE device request failed: \(message)") }
        }
        engine.onRadio={ _,_,_,source in if source==id { radioRead=true;print("BLE-only radio list read") } }
        engine.onAgentResult={ message in
            agentAccepted=message=="设备已接收提醒";print(agentAccepted ? "BLE-only Agent acknowledged" : "BLE-only Agent failed")
        }
        let deadline=Date().addingTimeInterval(90)
        let clock=DispatchSource.makeTimerSource(queue:.main)
        clock.schedule(deadline:.now(),repeating:.milliseconds(250))
        clock.setEventHandler {
            if settingsRead && settingsSaved && !startedAgent {
                startedAgent=true
                engine.notifyAgent(AgentEvent(agent:.codex,kind:.completed,session:"ble-device-test",key:AgentEvent.digest("ble-device-test"),project:""))
            }
            let complete=firstConnected.map { Date().timeIntervalSince($0)>60 } ?? false
            if Date()>=deadline || failed || complete {
                let success=complete && !failed && settingsRead && settingsSaved && radioRead && agentAccepted && Date().timeIntervalSince(lastConnected)<3
                clock.cancel();engine.stop()
                print("BLE-only acceptance: settings=\(settingsRead) saved=\(settingsSaved) radio=\(radioRead) agent=\(agentAccepted) stable=\(success)")
                DispatchQueue.main.asyncAfter(deadline:.now()+1) { exit(success ? 0 : 1) }
            }
        }
        clock.resume();engine.start();dispatchMain()
    }
}
