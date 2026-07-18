# 正方形封面与全屏列表实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [x]`）语法来跟踪进度。

**目标：** 保证 Cover Flow 封面始终为正方形，并将歌曲列表改为只显示当前集合名称的全屏模式，使用封面放大动画连接两者。

**架构：** `PlayerPage` 使用一个动画进度同时驱动封面层的放大淡出和列表层的淡入。Cover Flow 通过 `AspectRatio(1)` 锁定封面，列表层使用独立顶栏并保留现有悬浮播放器。

**技术栈：** Flutter Material、AnimationController、AnimatedBuilder、Widget Tests。

---

### 任务 1：定义布局合同

**文件：**
- 修改：`test/player_app_test.dart`
- 修改：`lib/player_page.dart`

- [x] **步骤 1：编写失败测试**

在 Widget 测试中读取 `cover-art` 的尺寸，断言宽高相等；进入列表后断言 `fullscreen-track-list` 存在、`library-header` 不存在、`collection-title` 显示当前名称。

- [x] **步骤 2：确认红灯**

```bash
flutter test test/player_app_test.dart
```

预期：因缺少新的稳定 Key 和全屏布局而失败。

- [x] **步骤 3：实现最小布局修改**

为中心封面使用 `AspectRatio(aspectRatio: 1)`；将列表页改为包含当前集合名称顶栏的独立全屏层，不渲染分类顶栏。

- [x] **步骤 4：确认绿灯**

```bash
flutter test test/player_app_test.dart
```

预期：新布局测试通过。

### 任务 2：实现封面全屏化动画

**文件：**
- 修改：`lib/player_page.dart`
- 修改：`test/player_app_test.dart`

- [x] **步骤 1：编写失败测试**

进入列表后在动画中点断言 `cover-expansion` 与 `fullscreen-track-list` 同时存在；完成后只显示列表；系统返回后恢复原封面。

- [x] **步骤 2：确认红灯**

```bash
flutter test test/player_app_test.dart
```

预期：因尚未存在可逆的展开动画而失败。

- [x] **步骤 3：实现可逆过渡**

在 `_PlayerPageState` 中加入 420ms `AnimationController`；上滑时加载曲目并正向播放，返回手势时反向播放。封面层在前 70% 放大淡出，列表层在后 60% 淡入。

- [x] **步骤 4：全量验证**

```bash
flutter test
dart analyze lib test
dart format --output=none --set-exit-if-changed lib test
git diff --check
```

预期：所有命令退出码为 0。Android/Rust 发布构建推送后由 GitHub Actions 验证。
