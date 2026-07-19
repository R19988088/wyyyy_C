# 封面转轮与标题宽度实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在封面下方加入复用现有速度算法的隐藏循环转轮，并修复标题宽度。

**架构：** 将指针圆周角度差转换为切向像素位移，传给现有 `CoverScrubSpeedController`。页码使用模运算循环；文字宽度使用已计算的 `coverSize`。

**技术栈：** Flutter、Dart、`flutter_test`。

---

### 任务 1：圆周输入和循环翻页

**文件：**
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写失败的 Widget 测试**

添加测试：从转轮右侧开始，按顺时针移动指针并跨越多个采样点，确认同一手势持续翻页；再从末尾顺时针移动并确认循环到第一张，逆时针从第一张循环到最后一张。

- [ ] **步骤 2：运行测试验证正确失败**

运行：`flutter test test/player_app_test.dart --plain-name 'hidden wheel'`

预期：FAIL，焦点封面未按圆周手势变化或未循环。

- [ ] **步骤 3：实现最小圆周输入**

在 `_PlayerPageState` 保存上一指针角度；在转轮区用 `Listener` 获取本地坐标，角度差换算为圆周切向位移后调用 `scrubSpeed.update`。将目标索引计算改为 `((current + step) % count + count) % count`，保留现有动画时长和曲线。

- [ ] **步骤 4：运行定向测试**

运行：`flutter test test/player_app_test.dart --plain-name 'hidden wheel'`

预期：PASS。

### 任务 2：标题宽度

**文件：**
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：编写失败的宽度测试**

为封面标题区加 key，测量其宽度并断言与当前封面宽度一致。

- [ ] **步骤 2：运行测试验证正确失败**

运行：`flutter test test/player_app_test.dart --plain-name 'cover caption uses the cover width'`

预期：FAIL，当前文字区宽度只有 `PageView` 单页宽度。

- [ ] **步骤 3：使文字区与封面等宽**

用宽度为 `coverSize` 的 `SizedBox` 包裹标题和副标题，文本居中并保留单行省略。

- [ ] **步骤 4：运行定向测试**

运行：`flutter test test/player_app_test.dart --plain-name 'cover caption uses the cover width'`

预期：PASS。

### 任务 3：回归验证与推送

**文件：**
- 修改：`lib/player_page.dart`
- 测试：`test/player_app_test.dart`

- [ ] **步骤 1：格式化与静态检查**

运行：`dart format lib/player_page.dart test/player_app_test.dart && dart analyze lib test`

预期：格式无额外变更，分析为 `No issues found!`。

- [ ] **步骤 2：运行全量 Flutter 测试**

运行：`flutter test`

预期：全部 PASS。

- [ ] **步骤 3：提交并推送**

```bash
git add docs/superpowers/specs/2026-07-19-cover-wheel-title-width-design.md docs/superpowers/plans/2026-07-19-cover-wheel-title-width.md lib/player_page.dart test/player_app_test.dart
git commit -m "feat: add circular cover wheel navigation"
git push origin main
```

预期：推送成功并触发仓库 Action。
