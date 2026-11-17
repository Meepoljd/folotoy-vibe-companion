**简体中文** · [English](install.md)

# 在 Mac 安装 Vibe 伴侣

支持 **macOS 13+**，Apple Silicon 和 Intel 通用。从
[GitHub Releases](https://github.com/lialun/folotoy-vibe-companion/releases/latest) 下载 DMG 或 ZIP。

1. **安装：**把 **Vibe 伴侣.app** 拖入“应用程序”，从那里打开。
   更新时先退出旧版，再替换 App。
2. **允许打开：**若被系统拦截，进入**系统设置 → 隐私与安全性 → 仍要打开**。
   若提示“已损坏”且没有“仍要打开”，确认文件来自本项目 Release，核对附件
   `SHA256SUMS.txt` 后，在终端执行以下命令，再重新打开：

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Vibe 伴侣.app"
   ```

3. **连接设备：**安装配套固件，在 App 点击设备的“连接”，再在设备上按上键确认。
   同一设备的 Wi-Fi／BLE 合并显示，可同时连接并自动切换。允许局域网／蓝牙访问。
   换电脑也通过设备确认，详见[设备连接](connections.zh_CN.md)。
4. **配置语音（可选）：**安装 [BlackHole 2ch](https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg) 和
   [微信输入法](https://z.weixin.qq.com/)。安装 BlackHole 后重启电脑，再在输入法中
   将麦克风选为 **BlackHole 2ch**，
   “按住说话”设为**左 Control＋左 Option＋V**，Vibe 伴侣中保持相同快捷键。
   在**系统设置 → 隐私与安全性 → 辅助功能**中开启 **Vibe 伴侣**。
   只用 Agent 提醒时跳过本步。

更新后若辅助功能已勾选，App 仍提示未授权，删除旧条目，再添加“应用程序”中的新版 App。

保持电脑唤醒，选中输入框。按住设备上键说话，松开结束，短按下键回车。
关闭窗口后 App 仍在菜单栏运行；退出 App 才停止接收。App 不使用钥匙串。
