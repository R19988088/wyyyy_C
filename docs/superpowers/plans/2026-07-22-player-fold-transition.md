# 播放器封面列表折叠过渡实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 用向上折叠的大封面和自下而上出现的封面列表替换现有缩放淡入过渡。

**架构：** 保持 `_CoverMode` 的两个常驻视图和 `AnimatedSwitcher` 状态边界。用一个具名的 `Transform` 容器替换封面缩放，并将列表切换的位移起点改为下方，使关闭动画由 Flutter 反向驱动。

**技术栈：** Flutter Material、widget tests。

---

### 任务 1：锁定折叠过渡结构

**文件：**
- 修改：`test/player_app_test.dart:449-490`

- [ ] **步骤 1：编写失败的测试**

```dart
expect(find.byKey(const Key('cover-flow-fold-transition')), findsOneWidget);
expect(find.byKey(const Key('album-switch-list-transition')), findsOneWidget);
```

- [ ] **步骤 2：运行测试验证失败**

运行：`flutter test test/player_app_test.dart --plain-name "list switching centers the selected album while the wheel is held"`

预期：FAIL，缺少两个折叠过渡容器。

### 任务 2：实现折叠和上移交接

**文件：**
- 修改：`lib/player_page.dart:460-510`

- [ ] **步骤 1：替换封面缩放容器**

```dart
Transform(
  key: const Key('cover-flow-fold-transition'),
  alignment: Alignment.bottomCenter,
  transform: Matrix4.identity()
    ..setEntry(3, 2, .001)
    ..rotateX(showingSwitchList ? -.78 : 0),
  child: _CoverFlow(...),
)
```

- [ ] **步骤 2：将列表从下方滑入并添加稳定键**

```dart
SlideTransition(
  key: const Key('album-switch-list-transition'),
  position: Tween<Offset>(
    begin: const Offset(0, .12),
    end: Offset.zero,
  ).animate(animation),
  child: child,
)
```

- [ ] **步骤 3：运行聚焦测试验证通过**

运行：`flutter test test/player_app_test.dart --plain-name "list switching centers the selected album while the wheel is held"`

预期：PASS。

### 任务 3：回归验证和发布

**文件：**
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [ ] **步骤 1：运行静态分析和完整测试**

运行：`dart analyze lib test && flutter test`

预期：两个命令均以 0 退出。

- [ ] **步骤 2：提交并推送主分支**

```bash
git add lib/player_page.dart test/player_app_test.dart docs/superpowers
git commit -m "feat: fold cover into album list"
git push origin main
```

- [ ] **步骤 3：验证发布 APK**

运行：`gh run watch <run-id> --exit-status && curl -fL -o downloads/wyyyy.apk https://github.com/R19988088/wyyyy_C/releases/download/continuous/wyyyy.apk`

预期：Action 成功，直接 APK 下载返回 0。
