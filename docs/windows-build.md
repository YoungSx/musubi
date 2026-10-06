# Windows 本地测试包

Musubi 0.5.0 使用 Godot 4.7.2 stable 的 Windows x64 导出模板。
测试者解压 ZIP 后双击 `Musubi.exe` 即可运行；`Musubi.pck` 必须与它放在一起。
目标电脑无需安装 Godot。当前包用于本地试玩，尚未做代码签名。

## 构建环境

- Windows x64、PowerShell 5.1 或更新版本、Git。
- Godot **4.7.2 stable** 标准版（GDScript），使用 console executable 构建。
- 与编辑器版本严格匹配的 **4.7.2.stable** 导出模板。

从 [Godot 官方 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
下载 `Godot_v4.7.2-stable_export_templates.tpz`，通过编辑器的导出模板管理器安装。
也可以把该 ZIP 格式归档中 `templates/` 下的文件解压到：

```text
%APPDATA%\Godot\export_templates\4.7.2.stable\
```

只构建 Windows x64 时，该目录至少需要 `version.txt`、
`windows_debug_x86_64.exe` 和 `windows_release_x86_64.exe`。
官方 release API 公布的整个模板归档 SHA256 为：

```text
f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011
```

用 `Get-FileHash -Algorithm SHA256 <archive.tpz>` 核对归档。
构建脚本使用已安装的模板，不会自动下载或修改全局工具链。

## 一键构建

在仓库根目录运行：

```powershell
# 本地试玩优先用 Debug，保留 Godot 的调试诊断。
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_windows.ps1 -Configuration Debug -RenderSmoke

# Release 使用正式导出模板。
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_windows.ps1 -Configuration Release -RenderSmoke
```

默认引擎位置是 `%USERPROFILE%\Tools\godot\Godot_v4.7.2-stable_win64_console.exe`。
其他安装位置可设置 `GODOT_EXE`，或传入 `-Godot 'C:\path\Godot_console.exe'`。
省略 `-Configuration` 时构建 Release。

每次构建依次执行资源导入、完整单元测试、Windows 导出和导出包的 headless 启动测试。
`-RenderSmoke` 额外使用实际图形驱动运行导出程序 120 帧；需要可用的桌面图形会话。
它检查进程退出与运行日志，视觉布局和鼠标操作仍需渲染截图、输入验证或人工试玩。
运行错误、非零退出或超时会让构建失败，日志保留供检查。
避免同时运行其他需要稳定窗口状态的截图验证。

## 产物与版本

```text
build/windows/<Debug|Release>/<UTC timestamp>/
  Musubi-<Git SHA>[-dirty]-windows-x64-<configuration>/
    Musubi.exe
    Musubi.pck
    build-info.json
    README.txt
  Musubi-<Git SHA>[-dirty]-windows-x64-<configuration>.zip
  Musubi-<Git SHA>[-dirty]-windows-x64-<configuration>.zip.sha256
  logs/
```

整个 `build/` 已被 Git 忽略；构建使用新目录，保留之前的测试包。
`build-info.json` 记录完整 Git revision、工作区是否存在修改、引擎版本、
构建时间、配置、启动测试结果，以及 EXE/PCK 的 SHA256。
`-dirty` 表示构建包含尚未提交的修改；可交付版本应在提交完成后重新构建。
ZIP 旁的 `.sha256` 用于核对分发文件。

## 日志与调试

- 构建日志：上述 `logs/` 中的 import、tests、export、smoke stdout/stderr。
- 包启动验证日志：`logs/runtime-headless.log`，启用渲染验证时另有 `runtime-rendered.log`。
- 正常双击运行日志：`%APPDATA%\Godot\app_userdata\Musubi\logs\godot.log`。
- 应用保存数据：`%APPDATA%\Godot\app_userdata\Musubi\`。

Debug 与 Release 使用相同场景、模拟和输入逻辑；Debug 模板保留额外引擎诊断，
Release 更适合接近发布条件的测试。分析性能时记录配置、设备和具体 Git revision，
不要直接把不同配置、不同显卡的数字混在一起。

当前默认使用 Mobile/Vulkan 渲染路径。构建机已验证 RTX 3070，其他 GPU、
Windows 缩放比例和驱动组合仍应使用实际测试包检查。
