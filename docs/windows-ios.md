# Windows 上的 iOS 构建路线核查

核查日期：2026-10-07。项目：Godot 4.7.2 / GDScript / Mobile renderer。

## 0.9.4 刚性携带（手机上的当前版本）

- 源码提交 `3649695`，成功构建
  [37897552655](https://github.com/YoungSx/musubi/actions/runs/37897552655)，2m57s。
  macOS CI `215 passed, 0 failed`，产物 `Musubi-iPhone-unsigned`（22,071,360 字节）
  下载后 SHA-256 与 CI 记录的 `50ffa4aa…877fa7` 一致。
- 这个 IPA 带上了携带手感的修复：拉取阶段仍按 `reel_speed` 限速，到位后锁定并
  直接要携带点本身，抓握用自己的 `carry_compliance` 而非绳子的手指默认值。
  原来的追逐式目标永远只在材料前面一步，走多久就拖多久。行为与量到的数字见
  [章鱼操作说明](octopus-play.md)。
- **安装要用 `--udid`，不要用 `--usb`。** 手机已解锁、`xtool devices` 也列得出设备
  的情况下，`install --usb` 仍然在 `[Preparing device]` 报
  `Operation not permitted` 或 `noDevice`；换成
  `install --udid <设备udid>` 后同一个包一次走完 Preparing
  device、Provisioning、Signing、Packaging、Connecting、Installing、Verifying，
  返回 `Successfully installed!`（exit=0）。解锁手机本身不足以解决，`--usb`
  在解锁后重试仍然失败，是选择器的差别。udid 用 `xtool devices` 取，
  本机的那一个写在不进仓库的 `build/ios/Reinstall-Musubi.cmd` 里，已改用 udid。
- **这次没有套 proxychains shim。** 本机现在直连 Apple 开发者 API 可用：
  WSL 里 `curl https://developerservices2.apple.com/` 返回 200，
  `ds teams` / `ds devices` / `ds certificates` / `ds profiles` 在 `LD_PRELOAD`
  未设置时全部正常返回。反过来，带上 shim 时 `xtool devices` 会报
  `Operation not permitted`，所以这层 shim 不能一直挂着。下文那段仍然保留：
  如果 provisioning 再次超时，照着重建，但要记得它会影响 usbmuxd 调用。
- `xtool launch --udid … XTL-5W6H7M2ZA3.com.youngsx.musubi` 返回
  `InstallationProxyClient.Error.unknown`（exit=1）。和 0.9.1 条目记的是同一类
  已知限制，位置更早了一步（之前是 `DebugserverClient.Error.unknown`）。
  这不是安装失败，但也**不是启动成功，更不是版本号确认**。本机没有装
  `pymobiledevice3` / `ideviceinstaller`，这次也没有用 Installation Proxy
  复查应用元数据——为了诊断去装包不在这次范围内。
- **携带手感在手机上仍未实测。** 桌面 `tools/verify_octopus.gd` 的 390×844
  渲染回放连跑五次 0 failures、携带残差 0.0011–0.0098 m，这是桌面结论，
  不代表触屏手感、持续帧率和内存验收。
- 签名材料状态：证书 `CKB74ADNQ8` 有效至 2027-10-07，profile `2C57C6KW4D`
  为 `ACTIVE`、2026-10-16 过期，覆盖本机证书与这台设备。免费 provisioning
  的 profile 只有 7 天，过期后需要重新签名安装。

## 0.9.4 瞄准反馈

- 源码提交 `3885fb6`，成功构建
  [37822096932](https://github.com/YoungSx/musubi/actions/runs/37822096932)。
  macOS CI `210 passed, 0 failed`，产物 `Musubi-iPhone-unsigned`（22,070,280 字节）
  下载后 SHA-256 与 CI 记录的 `6604f0ed…5ac6a1` 一致。
- 这个 IPA 带上了下面 `5108cbe` 条目里缺的两样东西：视平面锥角的抓取修复，
  以及按住右摇杆时的瞄准反馈（射线加落点环、无目标时只画暗射线、
  抓空时提示 1.6 s）。行为与边界见 [章鱼操作说明](octopus-play.md)。
- 套 proxychains shim 后签名并 USB 覆盖安装成功：xtool 返回
  `Successfully installed!`（exit=0），包含 Provisioning、Signing、Verifying 各阶段。
- `xtool launch --usb XTL-5W6H7M2ZA3.com.youngsx.musubi` 仍返回
  `DebugserverClient.Error.unknown`（exit=1），与 0.9.1 条目记的同一个已知限制。
  它在报错前打印了 `Launching Musubi...`，说明手机的 Installation Proxy
  能解析这个 bundle ID；但这不是启动成功，也不是版本号确认。
  本机没有装 `pymobiledevice3` / `ideviceinstaller`，这次没有像 0.9.1–0.9.4
  那样用 Installation Proxy 复查应用元数据。
- **摇杆抓取和瞄准反馈在手机上仍未实测。** 桌面 `tools/verify_octopus.gd`
  的 390×844 渲染回放 0 failures 是桌面结论，不代表触屏手感、持续帧率和内存验收。
- 这条记录写下时 `build/ios/Reinstall-Musubi.cmd` 带 proxychains shim、用
  `--usb` 选择设备、指向产物 `37822096932`。三处都已在 `3649695` 之后改掉，
  见本文件顶部条目。这两个脚本带机器绝对路径，落在 `.gitignore` 的 `/build/`
  下，只存在于本机，不进仓库；换机器要照下文那段重建。

## 0.9.4 章鱼操作

- 源码提交 `5108cbe`，成功构建
  [37759028343](https://github.com/YoungSx/musubi/actions/runs/37759028343)。
- macOS CI `200 passed, 0 failed`。仓库只有
  `.github/workflows/build-ios.yml` 一条 macOS workflow，Windows 为本机运行，
  没有 Windows CI。
- IPA 使用原账户签名覆盖安装成功：xtool 返回 `Successfully installed!`（exit=0），
  手机 Installation Proxy 确认 `Musubi` / 版本 `0.9.4` / build `0.9.4` /
  MinOS `16.0`，bundle 为 `XTL-5W6H7M2ZA3.com.youngsx.musubi`。
- 新默认场景是 `scenes/main/octopus_play.tscn`：双虚拟摇杆驱动第三人称章鱼，
  左摇杆在地面和人偶表面行走攀爬，右摇杆甩出弹性手臂抓绳、点击松手。
  触屏拖拽的 `play.tscn` / `main.tscn` 原样保留。行为与边界见
  [章鱼操作说明](octopus-play.md)。
- **已装到手机上的 `5108cbe` 不能用摇杆抓住绳子。** 瞄准摇杆只有两轴，方向
  完全落在镜头视平面上不含深度，而当时的 `OctopusGrab.pick` 拿这个方向与
  完整三维偏移比较锥角：站在人偶上实测 cosine 0.619 对阈值 0.819，视野内
  任何绳索材料都过不了锥角，放宽角度也没用。修复是把锥角改到手势所在的
  视平面上测量（距离排序仍在世界空间），**不在这个 IPA 里**。
  手机上的抓取需要重新构建、重新安装后才能验证。
- 修复后的工作区本机 `tests/run_tests.gd` `202 passed, 0 failed`，
  `tools/verify_octopus.gd` 的 390×844 渲染回放连续十次 0 failures。十次而不是
  一次：抓取落在甩动指到的地方，记录到的落点在 0.48 m 到 0.80 m 之间，
  单次干净跑不出边界成立还是样本走运。这是桌面结论；真实触屏手感、持续帧率
  和内存仍待用户实测，不将桌面回放报告为手机手势验收。
- 这条记录写下时 `build/ios/Reinstall-Musubi.cmd` 指向本次产物
  `37759028343`，且 xtool 调用没有带下文的 proxychains shim，按现状直接运行
  会复现 provisioning 超时。两者都已在 `3885fb6` 之后修好，见本文件顶部条目。

## 0.9.3 辅助跟随镜头

- 源码提交 `fcbebcb`，成功构建
  [37647051603](https://github.com/YoungSx/musubi/actions/runs/37647051603)。
- macOS CI `170 passed, 0 failed`；辅助跟随、多指竖屏、自由模式鼠标回放通过。
  行为与边界见 [辅助镜头说明](assisted-camera.md)。该条原记为
  “Windows 和 macOS CI 均为”，但仓库从未有过 Windows workflow，
  Windows 结果来自本机运行。
- IPA 校验后使用原账户签名覆盖安装成功，手机应用元数据确认 `Musubi` / `0.9.3`。
- 新场景默认 `Assisted follow`，Menu 的 Camera 部分可切换 `Free camera`；
  真实触屏手感交由用户试用，本次不将桌面回放报告为手机手势验收。
- 本地续签脚本已更新到本次产物。

## 0.9.2 触屏更新

- 源码提交 `e64e0ee`，成功构建
  [37638619226](https://github.com/YoungSx/musubi/actions/runs/37638619226)。
- macOS CI `161 passed, 0 failed`；同上，Windows 结果来自本机运行而非 CI。
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
- xtool 不在 PATH 上。它是解包后的 AppImage，入口是
  `/home/shangxin/.local/share/musubi-ios/squashfs-root/AppRun`
  （symlink → `usr/bin/xtool`，1.21.0）。按 `xtool` 这个名字搜索整台机器都找不到，
  必须用这个绝对路径调用。

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

### 本机网络：provisioning 走不通时的 proxychains shim

**先试直连。** 2026-10-09 实测本机直连 Apple 开发者 API 可用，
`3649695` 的签名安装没有用 shim 就跑通了，判断依据见本文件顶部条目。
下面这段是直连超时时的退路，不是默认配置——带上 shim 时 `xtool devices`
会报 `Operation not permitted`，所以它不能一直挂着，只在 provisioning
真的走不通时临时套上。

退路的由来：此机器曾经直连 Apple 开发者 API 超时，代理是唯一出口；而 xtool 用
自己的 Swift HTTP 客户端（AsyncHTTPClient），**不读 `http_proxy` / `https_proxy`**，
设这些变量对它无效。可行的做法是用户目录下的 proxychains-ng `LD_PRELOAD` shim
钩住 `connect()`，不动 `/etc/hosts`、不占 443、不需要 root：

```bash
WORK=$HOME/.local/opt/proxychains
export LD_PRELOAD=$WORK/root/usr/lib/x86_64-linux-gnu/libproxychains.so.4
export PROXYCHAINS_CONF_FILE=$WORK/proxychains.conf
export PROXYCHAINS_QUIET_MODE=1
export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
/home/shangxin/.local/share/musubi-ios/squashfs-root/AppRun install --usb <ipa路径>
```

`proxychains.conf` 的首条 `localnet 127.0.0.0/255.0.0.0` 让 usbmuxd 的
`127.0.0.1:27015` 保持直连，`[ProxyList]` 里的 `socks5 127.0.0.1 7890`
只承载 provisioning 流量；两者不能互换。`3885fb6` 的签名与安装是这样跑通的，
`3649695` 则是直连跑通的。

即便有 localnet 这一条，实测带 shim 时 `xtool devices` 仍会报
`Operation not permitted`，所以它只适合在 provisioning 阶段临时套上，
不要留在安装脚本里。`build/ios/Reinstall-Musubi.cmd` 现在不带 shim；
`apple-login.sh` 仍带着，因为 `auth login` 走的是同一条 Apple 网络，
真遇到超时时它是需要的那一个。

这两个脚本和 proxychains 本身都不在仓库里：脚本带机器绝对路径、落在
`.gitignore` 的 `/build/` 下，proxychains 装在 `$HOME/.local/opt/proxychains` 且不是
系统包。换机器时按上面这段重建，不要指望从仓库里拿到它们。

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
