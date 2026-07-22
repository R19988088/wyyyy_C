# 封面手势重映射实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 用纵向专辑排序和水平封面/歌曲列表切换替代 Cover Flow 的用户水平翻页，并删除失效的模式设置。

**架构：** 保留 `PageController` 供程序化专辑定位，禁止 `PageView` 用户滚动。封面内容层将纵向位移送入现有专辑浏览链路，水平滑动打开歌曲列表；歌曲列表水平滑动调用现有关闭链路。

**技术栈：** Flutter、Dart、`flutter_test`。

---

### 任务 1：删除模式设置

**文件：**
- 修改：`lib/main.dart`
- 修改：`lib/settings_page.dart`
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：把设置测试改为断言模式选项不存在**

打开设置页，断言找不到 `album-switch-view`、`切换专辑时`、`封面` 和 `列表`。

- [ ] **步骤 2：运行测试确认失败**

运行：`flutter test test/player_app_test.dart --plain-name 'settings omits the obsolete album switching view'`

预期：FAIL，当前设置页仍显示分段选项。

- [ ] **步骤 3：删除最少状态链路**

删除 `PlayerApp`、`SettingsPage`、`PlayerPage` 中的 `listCoverSwitching` 参数、state、回调和 `SharedPreferences` 读写；专辑排序列表改为只依赖 `coverPressed`。

- [ ] **步骤 4：运行设置测试**

运行：`flutter test test/player_app_test.dart --plain-name 'settings omits the obsolete album switching view'`

预期：PASS。

### 任务 2：封面纵向浏览专辑

**文件：**
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写封面上下拖动失败测试**

在大封面上向上分段拖动，断言出现 `album-switch-list`、浏览索引增加且松手后恢复新封面；再向下拖动并断言索引减小。全过程断言 `player-metadata` 曲目不变。

- [ ] **步骤 2：运行测试确认失败**

运行：`flutter test test/player_app_test.dart --plain-name 'vertical cover drag browses albums without playing'`

预期：FAIL，当前竖滑会打开歌曲列表或不会浏览专辑。

- [ ] **步骤 3：复用现有浏览链路实现纵向手势**

封面内容层在纵向拖动开始时调用 `_setScrubberActive(true)`，更新时把 `-delta.dy` 与当前帧时间传给 `_scrubCovers`，结束或取消时调用 `_setScrubberActive(false)`。删除原竖滑打开歌曲列表路径。

- [ ] **步骤 4：运行纵向手势测试**

运行：`flutter test test/player_app_test.dart --plain-name 'vertical cover drag browses albums without playing'`

预期：PASS。

### 任务 3：水平切换封面与歌曲列表

**文件：**
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写水平切换失败测试**

分别在封面上向左、向右拖动，断言都打开 `fullscreen-track-list` 且浏览专辑不变；分别在歌曲列表上向左、向右拖动，断言都返回封面。

- [ ] **步骤 2：运行测试确认失败**

运行：`flutter test test/player_app_test.dart --plain-name 'horizontal swipe toggles the cover and track list'`

预期：FAIL，当前水平拖动仍翻专辑或歌曲列表不响应横滑。

- [ ] **步骤 3：实现方向无关的水平切换**

为封面内容层添加水平滑动结束回调调用 `_openList`，为 `_FullscreenTrackList` 外层添加水平滑动结束回调调用 `_closeList`。给封面 `PageView` 设置 `NeverScrollableScrollPhysics`，删除页面拖动视觉状态。

- [ ] **步骤 4：运行水平切换和纵向列表回归测试**

运行：`flutter test test/player_app_test.dart --plain-name 'horizontal swipe toggles the cover and track list'`

运行：`flutter test test/player_app_test.dart --plain-name 'track list shows metadata numbers and active progress fill'`

预期：全部 PASS。

### 任务 4：验证与发布

**文件：**
- 修改：`lib/main.dart`
- 修改：`lib/settings_page.dart`
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [ ] **步骤 1：格式化、分析和完整测试**

运行：`dart format lib/main.dart lib/settings_page.dart lib/player_page.dart test/player_app_test.dart && dart analyze lib test && flutter test`

预期：分析无问题，全部测试通过。

- [ ] **步骤 2：提交并推送 `main`**

提交代码和文档并推送 `main`，触发 `Android Release APK`。

- [ ] **步骤 3：验证 APK 发布**

等待对应 commit 的 Action 成功，确认 `continuous` tag 指向该 commit，`wyyyy.apk` 使用固定证书且直接下载返回 Android APK 内容类型。

