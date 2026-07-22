# 播放器手势与封面列表实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 消除大封面横纵拖拽竞争，将封面列表改成带震动的自由滚动列表，并在双击时恢复目标曲库的播放位置。

**架构：** 用单一指针方向门控协调大封面水平和垂直入口，方向一经锁定不再改变。列表使用 Flutter 原生 `ListView`，滚动通知只负责跨行震动；播放恢复复用现有 Rust `SavedPosition` 存储。

**技术栈：** Flutter、Dart widget tests、Rust store、GitHub Actions。

---

### 任务 1：锁定方向手势

**文件：**
- 修改：`test/player_app_test.dart`
- 修改：`lib/player_page.dart`

- [ ] 添加失败测试：明显水平手势只打开歌曲列表，明显垂直手势只打开封面列表，模糊斜向手势不触发切换。
- [ ] 运行聚焦测试并确认因现有双识别器竞争而失败。
- [ ] 用一个方向门控器在超过触摸阈值且主方向达到 1.5 倍时锁定，并只分派对应方向。
- [ ] 重跑聚焦测试并确认通过。

### 任务 2：实现自由滚动封面列表

**文件：**
- 修改：`test/player_app_test.dart`
- 修改：`lib/player_page.dart`

- [ ] 添加失败测试：列表没有固定中间条，滚动后条目保持自然位置且每跨一行发送一次封面反馈。
- [ ] 运行聚焦测试并确认失败。
- [ ] 将居中 Stack 列表替换为 `ListView.builder`，用滚动偏移跨越 `rowExtent` 的次数发送反馈。
- [ ] 重跑聚焦测试并确认通过。

### 任务 3：恢复每个曲库的歌曲与进度

**文件：**
- 修改：`test/player_app_test.dart`
- 修改：`test/rust_player_repository_test.dart`
- 修改：`lib/player.dart`
- 修改：`lib/rust_player_repository.dart`

- [ ] 添加失败测试：双击任意列表项会激活它；目标曲库有记录时恢复记录中的歌曲索引和秒数，无记录时从头开始。
- [ ] 运行聚焦测试并确认失败。
- [ ] 扩展播放仓库激活路径，使其读取目标 `kind:id` 的现有保存记录并在装载队列后 seek。
- [ ] 双击列表项时先浏览到该项，再激活并关闭列表。
- [ ] 重跑聚焦测试并确认通过。

### 任务 4：验证和发布

**文件：**
- 修改：以上实现和测试文件。

- [ ] 运行 `dart format --output=none --set-exit-if-changed lib test`、`dart analyze lib test`、`flutter test` 和相关 Rust 测试。
- [ ] 审查最终 diff，提交并推送 `main`。
- [ ] 等待对应 commit 的 `Android Release APK` Action 成功。
- [ ] 确认 continuous release 的 `wyyyy.apk` 直链可下载，下载到 `downloads/wyyyy.apk` 并记录 SHA-256。
