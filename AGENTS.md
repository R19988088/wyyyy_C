# 交付规则

- 需要 Android APK 时，只能通过仓库 GitHub Actions 构建；不在本地构建。
- 代码或配置变更完成后，提交并推送 `main` 以触发 `Android Release APK` Action。
- 等待对应 commit 的 Action 成功。Action 必须把 `wyyyy.apk` 作为 `continuous` release 的直接资产发布，不使用需要跳转的页面或 ZIP；交付时提供直接下载链接并确认可下载。
- 对 APK 交付请求，在确认直链可下载后，下载同一文件到工作区 `downloads/wyyyy.apk`，并保留其 SHA-256 供核对。
- 不将 APK 打包为 ZIP，保留现有固定签名。
- 面向用户的最终输出仅包含直接 APK 下载链接；仅在出现错误时输出错误信息。
