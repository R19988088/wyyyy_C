# Flutter + Rust 原生播放器迁移设计

## 目标

将当前 Tauri WebView 播放器迁移为 Flutter 原生 GPU UI + Rust Core，保持网易云登录、资料、收藏列表、播放恢复和固定签名发布能力，并加入流畅 Cover Flow、完整播放栏、永久媒体缓存、系统媒体控制及标准 Android 后台播放。

## 技术边界

- Flutter/Impeller 负责 Android、iOS、Windows、macOS、Linux UI，不使用 WebView 承载主界面。
- Rust 保留网易云 WEAPI/EAPI、Cookie、二维码登录、资料解析、列表和播放地址解析，通过 `flutter_rust_bridge` 暴露异步 API。
- 液态玻璃复用本地 `/Users/ddd/Documents/ai/PiliPlus` 已验证的 `liquid_glass_widgets` 初始化、`GlassBackdropScope` 和 `GlassContainer` 模式。
- Android 播放由后台 `AudioHandler` 持有 `media_kit` Player，Activity 生命周期不停止媒体服务。
- 不请求忽略电池优化；使用标准 `mediaPlayback` 前台服务、MediaSession、音频焦点、媒体通知和 WakeLock。

## 交互

- 封面拖动采用 Apple Music 式连续插值：拖动距离直接驱动位置、缩放、轻微 Y 轴透视、亮度和阴影；松手按速度与距离吸附。
- 横向浏览不切歌，只有再次点击中心封面才切换播放集合。
- 底部播放器为悬浮大圆角玻璃矩形。第一行显示封面、标题、歌手；第二行独立放置上一首、播放/暂停、下一首；第三行显示进度。
- 双击标题/歌手区跳回当前播放集合。若目标距离较远，先瞬时定位到目标前后 2-3 张，再用可见的 Cover Flow 动画滑到目标，不闪现。
- 曲目分割线使用当前前景色 10% 不透明度。

## 缓存

- Rust 按账号持久化专辑、歌单、播客和曲目元数据。启动立即展示缓存，网络成功后后台刷新。
- 封面由专用 Flutter CacheManager 保存在应用缓存目录，不按时间自动清除。
- 音频按账号与曲目 ID 保存到应用缓存目录。首次播放使用网络流并并行落盘；下载完成后后续播放优先本地文件。
- 设置显示缓存大小并提供唯一的手动清理入口；退出登录不清除媒体缓存。

## 主题与系统栏

- 设置提供浅色/深色二态切换并持久化。
- Android edge-to-edge，状态栏背景使用黑色 30% 不透明度；状态栏图标亮暗随主题切换。
- 播放器与关键悬浮面使用真实液态玻璃；普通内容保持克制，避免全屏高成本玻璃采样。

## 发布与验证

- 本地只运行 Dart/Rust 静态检查和单元测试，不在本机生成 APK。
- GitHub Actions 构建 arm64 Release APK，固定签名，发布唯一 `wyyyy.apk` 资产。
- CI 验证 Rust、Flutter 测试、非 debuggable、arm64 ABI 和固定证书 SHA-256。
