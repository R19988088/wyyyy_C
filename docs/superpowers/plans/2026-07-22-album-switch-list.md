# 专辑切换列表实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 新增可持久化的“封面 / 列表”专辑切换类型，并在列表模式转动底部转盘时显示中央固定选中带的纵向专辑列表。

**架构：** `PlayerApp` 按现有主题和反馈设置模式持有布尔偏好并传给设置页与 `PlayerPage`。`PlayerPage` 继续使用既有浏览索引和转盘逻辑，仅在列表模式且转盘按下时把 Cover Flow 替换为由 `browsedIndex` 驱动的动画列表。

**技术栈：** Flutter、Dart、`shared_preferences`、`flutter_test`。

---

## 文件结构

- 修改 `lib/main.dart`：加载、保存并下传 `listCoverSwitching` 偏好。
- 修改 `lib/settings_page.dart`：加入“封面 / 列表”分段选择。
- 修改 `lib/player_page.dart`：在转盘按住期间展示中央固定选中列表。
- 修改 `test/player_app_test.dart`：覆盖设置回调、列表布局、浏览切换和不触发播放。

### 任务 1：设置选择与持久化

**文件：**
- 修改：`lib/main.dart`
- 修改：`lib/settings_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写失败的设置 Widget 测试**

用 `PlayerApp(initialListCoverSwitching: false, saveListCoverSwitching: ...)` 启动应用，打开设置，断言 `SegmentedButton<bool>` 选中“封面”；点击“列表”后断言保存回调收到 `true`。

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/player_app_test.dart --plain-name 'settings selects and saves the album switching view'`

预期：FAIL，`PlayerApp` 尚无列表切换参数或设置页找不到“列表”。

- [ ] **步骤 3：实现最少设置链路**

在 `PlayerApp` 增加 `initialListCoverSwitching`、`saveListCoverSwitching` 和对应 state；`SettingsPage` 增加 `listCoverSwitching` 与 `onListCoverSwitchingChanged`，用 `SegmentedButton<bool>` 展示 `false: 封面`、`true: 列表`。`main()` 从 `SharedPreferences.getBool('listCoverSwitching') ?? false` 加载，并用 `setBool` 保存。

- [ ] **步骤 4：运行定向测试验证通过**

运行：`flutter test test/player_app_test.dart --plain-name 'settings selects and saves the album switching view'`

预期：PASS。

### 任务 2：转盘列表视觉与浏览行为

**文件：**
- 修改：`lib/main.dart`
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写失败的列表 Widget 测试**

以 `initialListCoverSwitching: true` 启动。断言空闲时不存在 `album-switch-list`；按住 `cover-scrubber` 后断言列表出现、当前项的 `album-switch-selected-0` 位于列表中央、小封面 `album-switch-cover-0` 在文字左侧，且选中背景为 `colorScheme.inverseSurface`。

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/player_app_test.dart --plain-name 'list switching centers the selected album while the wheel is held'`

预期：FAIL，找不到 `album-switch-list`。

- [ ] **步骤 3：实现中央固定列表**

向 `PlayerPage` 和 `_CoverMode` 下传 `listCoverSwitching`。当 `listCoverSwitching && coverPressed` 时渲染 `_AlbumSwitchList`，否则渲染现有 `_CoverFlow`。列表只构建当前索引附近的行，行位置由 `(index - browsedIndex) * rowExtent` 计算；当前行使用 `inverseSurface/onInverseSurface`，每行复用现有封面缓存加载方式。

- [ ] **步骤 4：运行布局测试验证通过**

运行：`flutter test test/player_app_test.dart --plain-name 'list switching centers the selected album while the wheel is held'`

预期：PASS。

- [ ] **步骤 5：编写失败的切换与不播放测试**

按住并横向移动转盘跨过专辑，断言新的选中行仍位于列表中央且旧行沿纵向移开；抬手后列表消失、新浏览封面回到中央，同时 `player-metadata` 仍显示原播放曲目。

- [ ] **步骤 6：运行测试验证失败**

运行：`flutter test test/player_app_test.dart --plain-name 'list switching browses vertically and returns to the cover without playing'`

预期：FAIL，列表尚未随浏览索引更新或松手恢复行为不符合要求。

- [ ] **步骤 7：补齐最少动画与退出行为**

用 `AnimatedPositioned` 以现有转盘翻页时长移动列表行；不增加点击回调，不调用播放或列表跳转 API。转盘抬起沿用 `_setScrubberActive(false)` 恢复 Cover Flow。

- [ ] **步骤 8：运行列表相关测试**

运行：`flutter test test/player_app_test.dart --plain-name 'list switching'`

预期：全部 PASS。

### 任务 3：回归验证、提交与远程 APK

**文件：**
- 修改：`lib/main.dart`
- 修改：`lib/settings_page.dart`
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [ ] **步骤 1：格式化与静态检查**

运行：`dart format lib/main.dart lib/settings_page.dart lib/player_page.dart test/player_app_test.dart && dart analyze lib test`

预期：`No issues found!`。

- [ ] **步骤 2：运行完整 Flutter 测试**

运行：`flutter test`

预期：全部 PASS。

- [ ] **步骤 3：提交并推送 main**

```bash
git add docs/superpowers/specs/2026-07-22-album-switch-list-design.md docs/superpowers/plans/2026-07-22-album-switch-list.md lib/main.dart lib/settings_page.dart lib/player_page.dart test/player_app_test.dart
git commit -m "feat: add album list switching view"
git push origin main
```

预期：推送成功并触发 `Android Release APK`。

- [ ] **步骤 4：等待并验证发布资产**

等待该 commit 的 Action 成功，确认 `continuous` release 的 `wyyyy.apk` 资产属于该 commit，并对直接下载 URL 发起请求确认可下载。
