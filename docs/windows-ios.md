# Windows 上的 iOS 构建路线核查

核查日期：2026-10-06。项目：Godot 4.7.2 / GDScript / Mobile renderer。

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

## 当前机器

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
