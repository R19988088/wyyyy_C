# Android 签名

Android Release APK 使用固定 keystore 签名，keystore 本体不进入 Git 仓库。

## GitHub Secrets

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Actions 将 keystore 解码到 runner 的临时目录，先对 release APK 执行 `zipalign`，再用 `apksigner` 签名。工作流会校验证书指纹，指纹不一致时不会发布。

`continuous` Release 必须保持可变：`gh release upload --clobber` 会删除同名旧资产后上传新 APK，开启 GitHub Immutable Releases 后无法使用这个持续覆盖策略。

## 证书

- SHA-256: `0A:AF:C0:BA:08:91:64:85:61:EF:CC:32:EA:22:15:B8:4D:14:45:94:F6:4F:35:B2:D8:E3:1B:7E:B8:03:C0:B1`
- 本地备份: `/Users/ddd/Documents/ai/wyyyy_C_signing_backup/wyyyy-release.jks`
- 恢复说明: `/Users/ddd/Documents/ai/wyyyy_C_signing_backup/RECOVERY.txt`
- Store type: `JKS`
- Alias: `wyyyy`

恢复前先核对证书：

```bash
keytool -list -v \
  -keystore /Users/ddd/Documents/ai/wyyyy_C_signing_backup/wyyyy-release.jks \
  -alias wyyyy
```

重新写入 keystore Secret：

```bash
base64 < /Users/ddd/Documents/ai/wyyyy_C_signing_backup/wyyyy-release.jks \
  | gh secret set ANDROID_KEYSTORE_BASE64 --repo R19988088/wyyyy_C
```

密码从 `RECOVERY.txt` 恢复后，分别写入 `ANDROID_KEYSTORE_PASSWORD` 和 `ANDROID_KEY_PASSWORD`。Alias 写入 `ANDROID_KEY_ALIAS`。

轮换签名时必须同时更新四个 Secrets、工作流中的预期证书指纹和本文档。
