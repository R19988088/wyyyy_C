# 云音乐

基于 Tauri 2 和 Rust 的极简网易云音乐播放器，首版面向 Android。

## 功能

- 手机号验证码登录
- 读取登录账号的专辑、歌单和播客
- Cover Flow 封面浏览，浏览时不中断当前音乐
- 点击居中封面后切换播放并恢复该集合上次位置
- 上下滑动切换封面和曲目列表
- 启动时恢复上次集合、曲目、进度和播放状态

## 下载

GitHub Actions 只构建固定签名的 Release APK。最新版本可直接下载：

<https://github.com/R19988088/wyyyy_C/releases/download/continuous/wyyyy.apk>

## 开发

```bash
npm install
npm test
```

Android APK 不在本地编译。推送 `main` 或手动运行 `Android Release APK` 工作流后，Actions 会测试、构建、签名并更新 `continuous` Release。

签名恢复信息见 [docs/signing.md](docs/signing.md)。
