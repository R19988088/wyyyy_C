# Flutter + Rust 原生播放器迁移实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 以 Flutter 原生 GPU UI 替换 WebView，并保留 Rust 网易云核心，交付支持真液态玻璃、持久缓存、系统媒体控制和 Android 标准后台播放的固定签名 APK。

**架构：** Flutter 页面和 `media_kit` 播放器通过 `flutter_rust_bridge` 调用 Rust Core。Rust 负责协议与持久化，Flutter 负责 Impeller UI、媒体服务和封面缓存；Android 的播放实例归前台媒体服务所有，不依赖 Activity 生命周期。

**技术栈：** Flutter 3.44、Dart 3.12、Rust、flutter_rust_bridge、liquid_glass_widgets、media_kit、audio_service、audio_session、flutter_cache_manager。

---

### 任务 1：建立 Flutter/FRB 工程骨架

**文件：** `pubspec.yaml`、`lib/main.dart`、`rust/`、各平台目录、`.gitignore`

- [ ] 用 `flutter create --project-name wyyyy --org com.r19988088 --platforms android,ios,linux,macos,windows .` 生成缺失平台文件。
- [ ] 添加 Flutter、液态玻璃、媒体、缓存和 FRB 依赖。
- [ ] 将现有 Rust 模块迁入 `rust/src`，去掉 Tauri command 壳，保留协议、模型和存储测试。
- [ ] 生成 FRB 桥接代码并运行 `flutter analyze`、`flutter test`、`cargo test --manifest-path rust/Cargo.toml`。

### 任务 2：Rust Core 与持久缓存

**文件：** `rust/src/api.rs`、`rust/src/store.rs`、`rust/src/cache.rs`、`rust/src/tests.rs`

- [ ] 先添加测试，覆盖登录恢复、列表缓存命中、后台刷新结果写回、音频缓存路径和手动清理。
- [ ] 暴露二维码登录、手机号登录、资料、分类列表、曲目、播放地址、播放位置和缓存 API。
- [ ] 元数据按账号原子持久化；音频下载使用临时文件完成后原子改名。
- [ ] 运行 Rust 测试，确认损坏缓存降级为空而不破坏登录状态。

### 任务 3：Flutter 状态与 Cover Flow

**文件：** `lib/app_state.dart`、`lib/player_page.dart`、`lib/widgets/cover_flow.dart`、对应测试

- [ ] 先添加纯 Dart 测试，覆盖横向浏览不切歌、中心二次点击激活、上一首/下一首边界及远距离返回路径。
- [ ] 实现拖动连续插值与吸附动画，采用已确认的 Apple Music 式缩放/轻透视参数。
- [ ] 实现封面/列表纵向切换与双击标题区返回当前播放封面的 2-3 张预定位动画。
- [ ] 运行 `flutter test` 与 `flutter analyze`。

### 任务 4：玻璃播放栏、主题和缓存设置

**文件：** `lib/widgets/glass_player.dart`、`lib/settings_page.dart`、`lib/theme.dart`

- [ ] 复用 PiliPlus 的液态玻璃初始化和 backdrop scope，播放器使用悬浮大圆角矩形。
- [ ] 标题/歌手、上一首/播放/下一首、进度条分三行布局；曲目分割线为前景色 10%。
- [ ] 设置提供浅色/深色开关、登录、缓存大小和手动清理。
- [ ] Android 状态栏背景 30%，图标亮暗随主题同步。

### 任务 5：后台媒体与系统控制

**文件：** `lib/services/audio_handler.dart`、`lib/services/player_service.dart`、`android/app/src/main/AndroidManifest.xml`

- [ ] 先添加 handler 测试，覆盖系统上一首、下一首、播放、暂停、进度跳转。
- [ ] `AudioHandler` 自身持有 Player；页面仅订阅状态，不在 dispose/onDestroy 停止服务。
- [ ] 注册 `mediaPlayback` 前台服务、MediaSession、通知权限、音频焦点和 becoming-noisy 行为。
- [ ] 保持 `androidStopForegroundOnPause: false`，仅用户主动停止/退出应用播放时结束服务。

### 任务 6：Actions Release APK

**文件：** `.github/workflows/android-release.yml`、`docs/signing.md`

- [ ] Actions 安装 Flutter/Rust/Android target，运行 Dart 和 Rust 测试。
- [ ] 只构建 arm64 Release APK，沿用现有 secrets 和固定证书摘要。
- [ ] 发布 `continuous` Release 的唯一资产 `wyyyy.apk`，不上传 ZIP、debug APK 或源码包。
- [ ] 下载发布资产并核对 SHA-256、application id、debuggable=false、ABI 与签名。
