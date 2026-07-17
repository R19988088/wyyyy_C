# 极简网易云音乐播放器实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 构建手机号验证码登录、个人专辑/歌单/播客、Cover Flow 浏览、在线播放与跨启动位置恢复的 Tauri 2 Android 应用，并由 GitHub Actions 产出固定签名的直接下载 APK。

**架构：** 原生 TypeScript/CSS 负责单页界面、手势和一个 `HTMLAudioElement`；Rust Tauri 命令负责网易云加密请求、Cookie、媒体库解析、播放地址解析和账号隔离状态。前端浏览焦点与实际播放集合分离，所有集合位置按 `类型:ID` 持久化。

**技术栈：** Tauri 2、Rust 2021、reqwest、serde、tokio、Vite、原生 TypeScript/CSS、Node 内置测试、GitHub Actions、Android SDK `apksigner`。

---

## 文件结构

- `package.json`：前端、测试和 Tauri 命令。
- `index.html`：应用挂载点与基础元数据。
- `src/types.ts`：前后端共享的 TypeScript 数据形状。
- `src/player-state.ts`：可测试的浏览焦点、播放集合和恢复决策纯函数。
- `src/player-state.test.ts`：Cover Flow 与恢复状态测试。
- `src/api.ts`：Tauri `invoke` 的薄封装。
- `src/main.ts`：界面渲染、手势、音频事件与持久化编排。
- `src/styles.css`：Cover Flow、列表、设置抽屉、浅深色和降级动效。
- `src-tauri/Cargo.toml`：最小 Rust 依赖。
- `src-tauri/tauri.conf.json`：应用标识、窗口和 Android bundle 配置。
- `src-tauri/src/lib.rs`：Tauri 状态初始化与命令注册。
- `src-tauri/src/models.rs`：媒体库、集合、曲目和会话模型。
- `src-tauri/src/crypto.rs`：WEAPI/EAPI 加密。
- `src-tauri/src/netease.rs`：验证码、登录、媒体库、详情和播放 URL 客户端。
- `src-tauri/src/store.rs`：Cookie 与播放状态的账号隔离持久化。
- `src-tauri/src/commands.rs`：前端可调用命令。
- `.github/workflows/android-release.yml`：测试、Release APK 构建、固定签名和 Release 上传。
- `docs/signing.md`：签名备份、Secrets 名称和证书指纹恢复说明。

### 任务 1：创建 Tauri 2 最小骨架与前端状态机

**文件：** `package.json`、`index.html`、`src/types.ts`、`src/player-state.ts`、`src/player-state.test.ts`、`src-tauri/Cargo.toml`、`src-tauri/src/lib.rs`、`src-tauri/tauri.conf.json`

- [ ] **步骤 1：先写浏览与恢复失败测试**

```ts
import test from "node:test";
import assert from "node:assert/strict";
import { browseTo, confirmFocusedCollection, restoreLaunch } from "./player-state.ts";

test("browsing another cover keeps the active playback", () => {
  const next = browseTo({ focusedId: "album:1", activeId: "album:1" }, "album:2");
  assert.deepEqual(next, { focusedId: "album:2", activeId: "album:1" });
});

test("confirming the focused cover restores its saved track", () => {
  const next = confirmFocusedCollection(
    { focusedId: "playlist:2", activeId: "album:1" },
    { "playlist:2": { trackId: 22, index: 3, positionMs: 9100, updatedAt: 1 } },
  );
  assert.equal(next.trackId, 22);
  assert.equal(next.positionMs, 9100);
});

test("launch restores the last active collection and paused state", () => {
  assert.deepEqual(
    restoreLaunch({ collectionId: "podcast:4", trackId: 9, positionMs: 800, playing: false }),
    { collectionId: "podcast:4", trackId: 9, positionMs: 800, shouldPlay: false },
  );
});
```

- [ ] **步骤 2：运行测试并确认因模块缺失而失败**

运行：`node --experimental-strip-types --test src/player-state.test.ts`

预期：FAIL，`player-state.ts` 或导出函数不存在。

- [ ] **步骤 3：实现最小纯状态机并建立 Tauri 骨架**

```ts
export function browseTo(state: BrowserState, focusedId: string): BrowserState {
  return { ...state, focusedId };
}

export function confirmFocusedCollection(state: BrowserState, saved: SavedPositions) {
  return { collectionId: state.focusedId, ...(saved[state.focusedId] ?? { index: 0, positionMs: 0 }) };
}
```

`package.json` 只保留 `vite`、`typescript`、`@tauri-apps/api` 和 `@tauri-apps/cli`；不加入 UI、动画、状态管理或测试框架。

- [ ] **步骤 4：运行前端状态测试**

运行：`node --experimental-strip-types --test src/player-state.test.ts`

预期：3 个测试 PASS。

- [ ] **步骤 5：提交骨架**

```bash
git add package.json index.html src src-tauri
git commit -m "chore: scaffold Tauri music player"
```

### 任务 2：实现 Rust 网易云登录与媒体库

**文件：** `src-tauri/src/models.rs`、`src-tauri/src/crypto.rs`、`src-tauri/src/netease.rs`、`src-tauri/src/store.rs`、`src-tauri/src/commands.rs`、`src-tauri/src/lib.rs`

- [ ] **步骤 1：先写加密、Cookie 和解析失败测试**

```rust
#[test]
fn md5_password_matches_known_vector() {
    assert_eq!(md5_hex("123456"), "e10adc3949ba59abbe56e057f20f883e");
}

#[test]
fn login_cookies_require_music_u() {
    let headers = ["MUSIC_U=token; Path=/; HttpOnly", "__csrf=csrf; Path=/"];
    let cookies = extract_login_cookies(headers);
    assert_eq!(cookies.get("MUSIC_U").map(String::as_str), Some("token"));
}

#[test]
fn parses_personal_collections() {
    let json = r#"{"code":200,"playlist":[{"id":7,"name":"日常","coverImgUrl":"http://img","trackCount":2}]}"#;
    assert_eq!(parse_playlists(json).unwrap()[0].key, "playlist:7");
}
```

- [ ] **步骤 2：在 Actions 的 Rust 测试任务确认失败**

运行：`cargo test --manifest-path src-tauri/Cargo.toml`

预期：FAIL，测试引用的加密、Cookie 或解析函数不存在。

- [ ] **步骤 3：实现协议和存储**

实现以下 Tauri 命令：

```rust
#[tauri::command] async fn send_login_code(phone: String, country_code: String, state: State<'_, AppState>) -> Result<(), String>;
#[tauri::command] async fn login_with_code(phone: String, country_code: String, code: String, state: State<'_, AppState>) -> Result<Account, String>;
#[tauri::command] async fn load_library(state: State<'_, AppState>) -> Result<Library, String>;
#[tauri::command] async fn load_collection(key: String, state: State<'_, AppState>) -> Result<CollectionDetail, String>;
#[tauri::command] async fn resolve_stream(track_id: u64, state: State<'_, AppState>) -> Result<String, String>;
#[tauri::command] async fn logout(state: State<'_, AppState>) -> Result<(), String>;
```

端点固定为 NeriPlayer 已验证的网易云调用：验证码发送 `/weapi/sms/captcha/sent`、验证码登录 `/eapi/w/login/cellphone`、账号 `/weapi/w/nuser/account/get`、用户歌单 `/weapi/user/playlist`、收藏专辑 `/weapi/album/sublist`、订阅播客 `/weapi/djradio/get/subed`、详情和播放 URL 对应接口。

- [ ] **步骤 4：运行 Rust 单元测试**

运行：`cargo test --manifest-path src-tauri/Cargo.toml`

预期：全部 PASS，且无网络依赖。

- [ ] **步骤 5：提交后端**

```bash
git add src-tauri
git commit -m "feat: add NetEase account and library backend"
```

### 任务 3：实现 Cover Flow、列表、登录和播放器

**文件：** `src/api.ts`、`src/main.ts`、`src/styles.css`、`src/player-state.test.ts`

- [ ] **步骤 1：补充二次点击和手势阈值失败测试**

```ts
test("first side-cover click only focuses and second center click confirms", () => {
  const focused = handleCoverClick({ focusedId: "album:1", activeId: "album:1" }, "album:2");
  assert.equal(focused.effect, "focus");
  const confirmed = handleCoverClick(focused.state, "album:2");
  assert.equal(confirmed.effect, "confirm");
});

test("vertical swipe wins only when vertical travel is dominant", () => {
  assert.equal(classifySwipe(8, 72), "vertical");
  assert.equal(classifySwipe(72, 8), "horizontal");
  assert.equal(classifySwipe(8, 12), "none");
});
```

- [ ] **步骤 2：运行测试确认新行为失败**

运行：`node --experimental-strip-types --test src/player-state.test.ts`

预期：FAIL，`handleCoverClick` 和 `classifySwipe` 尚未实现。

- [ ] **步骤 3：实现完整界面**

`main.ts` 只维护一个应用状态对象和一个 `HTMLAudioElement`。Cover Flow 使用 CSS `transform: translateX(...) scale(...) rotateY(...)`，动画只改变 `transform` 与 `opacity`。指针事件结束时调用纯函数分类手势，浏览不会调用 `audio.pause()` 或修改 `src`。

设置抽屉使用有标签的国家代码、手机号、验证码输入框；发送按钮有 60 秒倒计时；错误在表单内显示。媒体库提供骨架、空状态、错误与重试。播放进度在 `timeupdate` 节流到 5 秒保存，并在暂停、切歌和 `visibilitychange` 时立即保存。

- [ ] **步骤 4：运行状态测试与前端构建**

运行：`npm test && npm run build`

预期：所有状态测试 PASS，Vite build exit 0。

- [ ] **步骤 5：提交界面**

```bash
git add src index.html
git commit -m "feat: build Cover Flow player interface"
```

### 任务 4：配置 Android、固定签名和直接 APK Release

**文件：** `src-tauri/gen/android/**`、`.github/workflows/android-release.yml`、`.gitignore`、`docs/signing.md`

- [ ] **步骤 1：生成 Android 工程但不在本地编译**

运行：`npm run tauri android init -- --ci`

预期：生成 `src-tauri/gen/android`；不执行 `android build`。

- [ ] **步骤 2：创建固定签名并写入仓库 Secrets**

生成一份 `wyyyy-release.jks`，上传 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEYSTORE_PASSWORD`。keystore 不进入 git；本地备份目录和证书 SHA-256 写入 `docs/signing.md`。

- [ ] **步骤 3：实现 Release 工作流**

工作流仅允许 `workflow_dispatch` 和 `main` push，依次执行：Node/Rust/JDK/Android 环境、`npm ci`、`npm test`、`cargo test`、`npm run tauri android build -- --apk --target aarch64`、`zipalign`、`apksigner sign`、`apksigner verify --print-certs`、SHA-256、`gh release upload continuous wyyyy.apk --clobber`。

Release 不存在时先执行：

```bash
gh release create continuous --prerelease --title "持续构建" --notes "固定签名的 Android Release APK"
```

禁止调用 `actions/upload-artifact`，确保 GitHub 不生成用户下载时的 ZIP 包。

- [ ] **步骤 4：检查工作流静态约束**

运行：`rg -n "assembleDebug|upload-artifact|debuggable true|debugImplementation" .github src-tauri/gen/android`

预期：无匹配。

- [ ] **步骤 5：提交发布配置**

```bash
git add .github .gitignore docs/signing.md src-tauri/gen/android
git commit -m "ci: publish fixed-signature Android APK"
```

### 任务 5：推送、Actions 验证和 APK 验收

**文件：** 只修复 Actions 实际暴露的问题，不增加功能。

- [ ] **步骤 1：检查完整差异和工作区**

运行：`git status -sb && git diff --check && git log --oneline --decorate -8`

预期：没有未提交文件或空白错误。

- [ ] **步骤 2：推送 main 并等待 Actions**

运行：`git push -u origin main`，随后 `gh run watch --repo R19988088/wyyyy_C --exit-status`。

预期：Android Release workflow 成功。

- [ ] **步骤 3：验证 Release 资产**

运行：`gh release view continuous --repo R19988088/wyyyy_C --json assets,url`

预期：资产名精确为 `wyyyy.apk`，不包含 ZIP。

- [ ] **步骤 4：下载远端 APK 并检查签名与包信息**

运行：`gh release download continuous --repo R19988088/wyyyy_C --pattern wyyyy.apk --dir /tmp/wyyyy-verify`，然后执行 `apksigner verify --print-certs`、`sha256sum` 和 `apkanalyzer manifest application-id`。

预期：签名证书指纹与 `docs/signing.md` 一致，包名为 `com.r19988088.wyyyy`，APK 未设置 debuggable。
