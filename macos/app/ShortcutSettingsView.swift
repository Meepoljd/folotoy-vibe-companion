import SwiftUI
import AppKit

struct InputMethodSettingsView:View {
    @State private var weType:URL?
    @State private var error=""
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let app=weType {
                Button {
                    let settings=app.appendingPathComponent("Contents/MacOS/WeTypeSettings.app")
                    guard FileManager.default.fileExists(atPath:settings.path) else {
                        error="请从微信输入法菜单打开“设置 → 语音输入”。";return
                    }
                    error=""
                    let configuration=NSWorkspace.OpenConfiguration();configuration.arguments=["--ShowVoiceInput"]
                    NSWorkspace.shared.openApplication(at:settings,configuration:configuration) { _,failure in
                        if failure != nil { DispatchQueue.main.async { error="打开失败，请从微信输入法菜单打开“设置 → 语音输入”。" } }
                    }
                } label: { Label("打开输入法设置",systemImage:"slider.horizontal.3") }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Text("从输入法菜单打开语音设置。").font(.system(size:11)).foregroundStyle(Palette.muted)
            }
            if !error.isEmpty { Text(error).font(.system(size:11)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }.onAppear(perform:refresh)
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        weType=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.tencent.inputmethod.wetype")
    }
}

struct ShortcutKeycaps:View {
    let spec:String
    var body:some View {
        HStack(spacing:5) {
            ForEach(Array(Shortcut.displayKeys(spec).enumerated()),id:\.offset) { _,label in
                Text(label).font(.system(size:12,weight:.medium,design:.monospaced))
                    .padding(.horizontal,9).padding(.vertical,7)
                    .background(Palette.background,in:RoundedRectangle(cornerRadius:6))
                    .overlay(RoundedRectangle(cornerRadius:6).stroke(Palette.line,lineWidth:1))
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel(Shortcut.displayKeys(spec).joined(separator:" + "))
    }
}
struct ShortcutSettingsView:View {
    @ObservedObject var model:AppModel
    @State private var editing=false
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                VStack(alignment:.leading,spacing:7) {
                    Text("按住说话快捷键").font(.system(size:11)).foregroundStyle(Palette.muted)
                    ShortcutKeycaps(spec:model.shortcut)
                }
                Spacer()
                Button("更改快捷键") { editing=true }.buttonStyle(.bordered).controlSize(.small)
            }
            Text("与输入法保持一致，注意区分左右键。")
                .font(.system(size:11)).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
            if Shortcut.hasElevatedConflictRisk(model.shortcut) {
                Label(Shortcut.guidance(model.shortcut),systemImage:"exclamationmark.triangle")
                    .font(.system(size:11)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(14).background(Palette.background.opacity(0.5),in:RoundedRectangle(cornerRadius:9))
            .sheet(isPresented:$editing) {
                ShortcutRecorderSheet(original:model.shortcut) { value in
                    model.shortcut=value;model.saveShortcut()
                }
            }
    }
}
private struct ShortcutRecorderSheet:View {
    let original:String
    let save:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var candidate=""
    @State private var recording=true
    @State private var error=""
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("更改按住说话快捷键").font(.system(size:19,weight:.semibold))
            Text(recording ? "按下组合键，Esc 取消。" : "确认后保存，并同步输入法设置。")
                .font(.system(size:12)).foregroundStyle(Palette.muted)
            ZStack {
                RoundedRectangle(cornerRadius:10).fill(Palette.background)
                RoundedRectangle(cornerRadius:10).stroke(recording ? Palette.accent : Palette.line,lineWidth:2)
                if recording {
                    Label("正在等待按键…",systemImage:"keyboard").foregroundStyle(Palette.accent)
                } else { ShortcutKeycaps(spec:candidate) }
                if recording {
                    ShortcutCaptureView(capture:{ value in candidate=value;recording=false;error="" },cancel:{ dismiss() },failure:{ error=$0 })
                        .frame(width:1,height:1)
                }
            }.frame(height:80)
            if !error.isEmpty { Text(error).font(.system(size:11)).foregroundStyle(.orange) }
            if !recording && Shortcut.hasElevatedConflictRisk(candidate) {
                Text(Shortcut.guidance(candidate)).font(.system(size:11)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
            }
            HStack {
                Button("恢复默认") { candidate="ctrl+option+v";recording=false;error="" }
                if !recording { Button("重新录入") { recording=true;error="" } }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存快捷键") { save(candidate);dismiss() }
                    .buttonStyle(.borderedProminent).disabled(recording || candidate==original || (try? Shortcut.resolve(candidate)) == nil)
            }.controlSize(.small)
        }.padding(24).frame(width:510).background(Palette.surface).foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.dark)
    }
}
private struct ShortcutCaptureView:NSViewRepresentable {
    let capture:(String)->Void
    let cancel:()->Void
    let failure:(String)->Void
    func makeNSView(context:Context)->CaptureView {
        let view=CaptureView();view.capture=capture;view.cancel=cancel;view.failure=failure;return view
    }
    func updateNSView(_ view:CaptureView,context:Context) {}
    final class CaptureView:NSView {
        var capture:((String)->Void)?,cancel:(()->Void)?,failure:((String)->Void)?
        private var held=Set<CGKeyCode>(),peak=[CGKeyCode](),completed=false
        override var acceptsFirstResponder:Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self=self else { return };self.window?.makeFirstResponder(self) }
        }
        override func performKeyEquivalent(with event:NSEvent)->Bool {
            guard window?.firstResponder === self,event.type == .keyDown else { return false }
            keyDown(with:event);return true
        }
        override func flagsChanged(with event:NSEvent) {
            guard !completed,Shortcut.modifiers[event.keyCode] != nil else { return }
            let mask=Shortcut.modifiers[event.keyCode]!
            let side=mask & 0xffff
            let down=event.modifierFlags.rawValue & UInt(side == 0 ? mask : side) != 0
            if down { held.insert(event.keyCode);peak=held.sorted() }
            else {
                held.remove(event.keyCode)
                if held.isEmpty && !peak.isEmpty { finish(peak) }
            }
        }
        override func keyDown(with event:NSEvent) {
            guard !completed,!event.isARepeat else { return }
            if event.keyCode==53 { completed=true;cancel?();return }
            guard Shortcut.codes.values.contains(event.keyCode),Shortcut.modifiers[event.keyCode]==nil else {
                peak=[];failure?("暂不支持这个按键，请使用字母、数字、空格或修饰键组合。");return
            }
            finish(Shortcut.recordingModifiers(UInt64(event.modifierFlags.rawValue))+[event.keyCode])
        }
        override func keyUp(with event:NSEvent) {}
        private func finish(_ keys:[CGKeyCode]) {
            guard let value=Shortcut.recordedSpec(keys) else { failure?("无法录入此组合，请重试。");return }
            completed=true;capture?(value)
        }
    }
}
