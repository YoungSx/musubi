# Windows 上的 iOS 构建路线核查

核查日期：2026-10-07。项目：Godot 4.7.2 / GDScript / Mobile renderer。

## 0.9.2 触屏更新

- 源码提交 `e64e0ee`，成功构建
  [37638619226](https://github.com/YoungSx/musubi/actions/runs/37638619226)。
- Windows 和 macOS CI 均为 `161 passed, 0 failed`。
- `tools/verify_multitouch.gd` 的 390×844 渲染回放通过：独立双抓点、
  额外双指环绕/缩放、额外三指平移、镜头平滑期间抓点不跳、越过 UI 松手、
  地面场景允许触屏环绕。旧鼠标 mannequin 回放也通过。
- IPA 校验后使用原签名账户覆盖安装成功；手机 Installation Proxy 返回
  `Musubi` / `0.9.2` / `User`。
- 手机上的实际多指操作手感、持续帧率和内存仍待用户实测；不能用桌面回放
  代替这些结论。下文首次安装的启动日志属于 0.9.1。
- 本地 `build/ios/Reinstall-Musubi.cmd` 已指向本次 0.9.2 产物。

## 已验证的云端构建路线

Windows 用户无需本地 Mac 或下载 Xcode：仓库的
`.github/workflows/build-ios.yml` 在 GitHub macOS runner 上导出并编译原生 iOS 应用。
`export_presets.cfg` 的 `iOS` preset 只导出 Xcode 工程，随后由 Xcode 生成未签名 IPA。
Apple 登录、开发签名和手机安装留在本机，不使用 GitHub Secrets。

- 成功构建：[37632979914](https://github.com/YoungSx/musubi/actions/runs/37632979914)，
  源码提交 `26acc52`。产物名称 `Musubi-iPhone-unsigned`，保留 7 天。
- 使用官方 Godot 4.7.2 macOS 编辑器及导出模板，并校验官方 SHA-512。
- runner 为 `macos-15`，明确选择 Xcode 26.3。默认 Xcode 16.4 缺少模板引用的
  Metal / CoreAnimation 符号，导致链接失败。
- `application/app_store_team_id="0000000000"` 仅用于未签名工程导出；
  它不是实际签名身份，不能直接将此 IPA 安装到普通 iPhone。
- 本机 WSL 的 xtool 1.21.0 已通过
  `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015` 连接 Windows Apple 设备服务，
  并识别 USB 连接的 iPhone 15 Pro。此机器 WSL 使用镜像网络，其他网络模式不一定适用。
- xtool 的 `auth login --mode password` 由用户在本机终端完成；
  `install <ipa路径>` 可为 IPA 签名并安装，不需要本地 Swift / Xcode SDK。
  不要将账户密码、验证码、签名密钥或登录令牌提交到仓库。

本次已完成 Apple 登录、签名和 USB 安装：xtool 返回 `Successfully installed!`，
随后通过手机的 Installation Proxy 再次确认 `Musubi` / `0.9.1` 已安装。
xtool 会将实际 bundle ID 改为 `XTL-<TeamID>.com.youngsx.musubi`，启动时必须使用
手机返回的实际 ID。用户随后开启开发者模式并重启，工具查询返回 `true`。
手机日志确认 Musubi 进程运行（PID 388），并持续向它的 UIWindow 分发触摸事件。
本次采集的 22:14:53–22:15:29 日志没有匹配到 `SCRIPT ERROR` / `USER ERROR` / `Fatal`。
这证明原生 App 已启动，不等于绳索交互、帧率、内存和完整触摸验收通过。
xtool 的自动启动命令在本机返回 InstallationProxy 错误；最终启动证据来自
已经运行的手机进程日志，不将该命令记作成功。

设备为 iPhone 15 Pro / iOS 27.2。普通开发签名应用需要用户在手机
“设置 → 隐私与安全性 → 开发者模式”开启该模式，并按提示重启确认。
如首次启动提示开发者不受信任，还需在“设置 → 通用 → VPN 与设备管理”
中信任本次签名账户。

下载本次产物：

```powershell
gh run download 37632979914 -n Musubi-iPhone-unsigned -D build/ios/artifacts/37632979914
```

下文保留的是本地 WSL 交叉编译调研，当前云端构建路线不依赖这些前置步骤。

## 结论

不拥有 Mac 也有本地构建 iOS 的技术路线。Windows 可通过 WSL 使用
Linux 交叉编译工具链；不能把“Godot 常规导出流程使用 Xcode”解释成
“所有构建方式都必须有 Mac”。但 Musubi 尚未完成这条路线的端到端验证。

## 已核实的上游能力

1. [Godot 常规 iOS 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)
   描述在 macOS/Xcode 上导出、编译、部署的流程。
2. [Godot 的 Linux iOS 交叉编译文档](https://docs.godotengine.org/en/stable/engine_details/development/compiling/cross-compiling_for_ios_on_linux.html)
   明确提供 Linux 编译 Godot iOS 的方法：从 Apple Xcode `.xip` 提取
   iPhoneOS SDK，使用 Clang、cctools-port、SCons 和 `OSXCROSS_IOS`。
   文档中的版本示例较旧，具体参数必须对照所用 Godot/SDK 版本验证。
3. [xtool 项目](https://github.com/xtool-org/xtool) 提供跨平台的 SwiftPM
   iOS 应用构建、签名、设备连接和 IPA 安装工具。
   [Linux/Windows 安装文档](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md)
   明确支持 WSL，要求 Swift、设备通信服务，以及 Apple 官网下载的 Xcode
   `.xip`。当前文档使用 Swift 6.4 / Xcode 27；以实际安装时的要求为准。

xtool 的 SwiftPM 应用构建能力不等于直接支持 Godot 的 `.xcodeproj`。
Godot 的引擎交叉编译也不等于已经完成应用入口链接、资源打包、签名和安装。
这两个环节需要分别验证，不能把已有 IPA 的侧载成功当成构建验证。

## 本地交叉编译调研时的机器快照（2026-10-06）

- Windows 能识别 USB 连接的 Apple iPad。
- 已安装 x86_64 Ubuntu WSL。
- WSL 中尚未找到 `swift`、`xtool`、`clang`、`scons`、`ideviceinfo`、`usbmuxd`。
- Windows Downloads 中未找到 Xcode `.xip`。
- 未验证 WSL USB 透传、Apple 登录、签名身份或 provisioning profile。
- 没有生成或安装 Musubi IPA；iPad 帧率、触摸和内存验收仍未完成。

## 后续实验顺序

1. 用户通过 [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode)
   登录并下载 Xcode `.xip`，在本地提供路径。SDK 不从非官方镜像获取。
   Apple 登录、双重认证及协议接受需要用户本人完成。
2. 在 WSL 准备工具链并提取 SDK。先验证最小 iOS 应用的编译、签名和 USB 安装，
   将环境问题与 Godot 集成问题分开定位。
3. 检查 Godot 4.7.2 的预编译 iOS 模板是否可复用；确定应用入口、静态库依赖、
   链接参数和项目 `.pck` 的打包方式。验证 xtool 能否直接承担相应打包流程，
   或是否需要单独的 Godot 链接/打包脚本。
4. 成功生成并安装 Musubi 后，运行绳索拖拽、双指手势、Reset 和 Debug，记录
   设备型号、系统版本、帧时间、模拟/网格耗时与持续内存变化。

当前不确定点是第 3 步的 Godot 应用封装兼容性。缺少 SDK 与签名环境时，
不能承诺该组合可直接产出当前项目的可安装 IPA。
