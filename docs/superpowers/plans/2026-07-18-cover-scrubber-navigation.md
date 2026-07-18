# 封面快速滚动与返回定位实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [x]`）语法来跟踪进度。

**目标：** 完成居中分类顶栏、隐藏速度分档封面滚动区、封面双击播放和精确的列表返回定位。

**架构：** 速度映射使用一个无 Flutter 依赖的小控制器，其余交互继续留在 `PlayerPage`。列表会话显式保存 collection 身份，反向动画前重建 PageController。

**技术栈：** Dart、Flutter GestureDetector、PageController、Widget Tests。

---

### 任务 1：速度与距离映射

**文件：**
- 新建：`lib/cover_scrubber.dart`
- 新建：`test/cover_scrubber_test.dart`

- [x] 先写慢速 22px 步进、快速倍率和 90ms 节流失败测试。
- [x] 运行 `flutter test test/cover_scrubber_test.dart` 确认红灯。
- [x] 实现最小 `CoverScrubSpeedController`，固定参考项目的阈值和倍率。
- [x] 重跑定向测试确认绿灯。

### 任务 2：顶栏、隐藏区与双击

**文件：**
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [x] 先写激活背景、居中几何、三点入口、隐藏区和单/双击行为失败测试。
- [x] 运行 `flutter test test/player_app_test.dart` 确认红灯。
- [x] 使用 `Stack + Center` 实现顶栏，在标题下接入拖动控制器，封面激活切换为 `onDoubleTap`。
- [x] 重跑定向测试确认绿灯。

### 任务 3：重写列表返回目标

**文件：**
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [x] 先将返回测试改为断言原 collection ID 的封面精确位于屏幕中心。
- [x] 运行测试并记录当前行为。
- [x] 进入列表时保存 kind/ID/index，退出前重建到目标页，再执行反向动画。
- [x] 运行 `flutter test`、`dart analyze lib test`、格式检查和 `git diff --check`。
