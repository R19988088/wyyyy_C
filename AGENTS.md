# 交付规则

- 需要 Android APK 时，只能通过仓库 GitHub Actions 构建；不在本地构建。
- 代码或配置变更完成后，提交并推送 `main` 以触发 `Android Release APK` Action。
- 等待对应 commit 的 Action 成功。交付时必须提供 `continuous` release 中 `wyyyy.apk` 的直接下载链接，并确认该链接可下载。
- 不将 APK 打包为 ZIP，保留现有固定签名。
- 面向用户的最终输出仅包含直接 APK 下载链接；仅在出现错误时输出错误信息。
