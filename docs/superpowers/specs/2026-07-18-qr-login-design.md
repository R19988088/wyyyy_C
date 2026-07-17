# 网易云二维码登录设计

## 目标

在设置页提供二维码和手机号两种登录方式，默认显示二维码，扫码成功后复用现有账号、媒体库和播放位置恢复流程。

## 交互

- 未登录时显示“二维码 / 手机号”分段切换，默认二维码。
- 二维码模式进入后立即创建二维码，每 2 秒检查一次。
- 显示“请使用网易云音乐扫码”“请在手机上确认”“二维码已过期”和可重试错误。
- 关闭设置、切换手机号模式或登录成功时停止轮询。
- 手机号登录保持现有行为。

## 后端

- Rust 调用 `/weapi/login/qrcode/unikey` 创建 key。
- 使用 key 生成 `https://music.163.com/login?codekey=<key>`，由 `qrcode` crate 输出本地 SVG data URL。
- Rust 调用 `/weapi/login/qrcode/client/login` 检查状态：`801` 等待扫码、`802` 等待确认、`803` 登录成功、`800` 过期。
- `803` 后验证 `MUSIC_U`，复制 Cookie 到主客户端，获取 profile 并原子保存 session。

## 验证

- Rust 单测覆盖状态码解析和二维码 data URL。
- TypeScript 单测覆盖默认二维码、轮询状态和关闭后停止轮询。
- GitHub Actions 完成 Rust 测试、Android Release 构建、固定签名和 APK 发布。
