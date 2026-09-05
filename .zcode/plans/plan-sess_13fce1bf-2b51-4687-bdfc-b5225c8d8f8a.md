# 修复三个问题：查看器面板漏图 / 面板下方死区 / 文件夹 tab 显示全部图片

## 根因（已探明）

**问题 1+2（查看器）**：底部面板 `DraggableScrollableSheet` 建在每个 PageView 页面内部（meme_viewer_screen.dart:327-330），每页各有一份 sheet 实例（各持独立的真实拖动高度），而图片区域裁剪、遮罩、底部色块用的是共享变量 `_panelExtent`。b903b59 翻页时只重置了共享变量，存活邻页的 sheet 实际仍停在拖到最高的 1.0；且 `_syncExtentTo`（L77-89）是单槽 post-frame 回调，被多个存活页面抢用导致测量值乒乓打架 → `_panelExtent` 与面板真实高度持续错位。错位时底部 `ColoredBox` 色块（L320-326）露出一截，颜色与菜单相同但无任何手势 → 就是"菜单下面那截不能滑"的死区。

**问题 3（主页）**：`home_screen.dart:59-62` 切文件夹 tab 不清 folderId，而 `meme_provider.dart:852` 在 `_showFoldersView` 为 true 时跳过文件夹过滤；UI（home_screen.dart:496-497）又因 `folderId != null` 渲染文件夹内容视图 → 全部图片显示在文件夹标题下。这是 aeccfef（tab 渲染改为显示文件夹内容）与旧过滤规则不匹配导致的。

## 修改 1：查看器面板改为全局单实例（meme_viewer_screen.dart）

核心：把面板从 PageView 页面内提升到 body 层，整个查看器只有一份 sheet，共享变量与真实高度不可能跨页错位。

1. **State 新增** `late DraggableScrollableController _panelController;`，initState 创建、dispose 释放。
2. **重排 build**（L255-338）：
   - `body` 改为：`LayoutBuilder`（取 bodyHeight、算 panelHeight，逻辑不变）→ `NotificationListener<DraggableScrollableNotification>`（不变）→ `Stack`：
     - `Positioned.fill(bottom: panelHeight)` 内直接放 **PageView.builder**（原来放的是单页图片区）；每页 itemBuilder 精简为 `ClipRect → GestureDetector(onTap: _toggleFullscreen) → _buildImageArea(m, i)`（保留 ClipRect 防 PhotoView 缩放溢出到邻页）；
     - `if (!_isFullscreen)` 分支的遮罩、ColoredBox 色块原样上移到这层 Stack；
     - `Align(bottomCenter) → _buildDraggableDetailPanel(theme, prov, _meme, l10n, bodyHeight)` 也上移——m 参数从"每页的 m"改为现有 `_meme` getter（带越界回退）。
   - `_buildDraggableDetailPanel` 本体（L1203 起）不动，仅给它传 `controller: _panelController`。
3. **翻页重置（按用户选择：每次翻页重置回初始高度）**：`onPageChanged` 保留重置语义但改为驱动真实高度：
   ```dart
   onPageChanged: (i) => setState(() {
     _currentIndex = i;
     _mangaPageIndex = 0;
     // 翻页时面板吸附回初始高度（单实例面板，直接驱动真实高度而非共享变量）
     if (_panelController.isAttached) _panelController.jumpTo(0.45);
   }),
   ```
   jumpTo 会触发 `DraggableScrollableNotification` → `_panelExtent` 同步更新 → 图片区域同步收缩，二者天然一致。
4. **保留** `_syncExtentTo` 与通知监听（单 sheet 后不再有跨页抢占，它们成为纯兜底：处理全屏退出后 sheet 重建、IME 弹出等约束变化）；保留底部 ColoredBox 色块（单实例下与 sheet 精确重合，作为圆角缺口与瞬态帧的兜底）。
5. UX 变化说明：翻页时面板不再随页面滑动（内容在中点切换），面板静止、图片在其下滑动——更接近标准详情面板行为。

## 修改 2：文件夹 tab 显示当前文件夹内容（meme_provider.dart，按用户选择）

`_apply()` L852 过滤条件从
```dart
if (_folderId != null && !_showFavorites && !_showFoldersView) {
```
改为
```dart
if (_folderId != null && !_showFavorites) {
```
并更新 L850-851 注释：文件夹 tab 现在也会渲染 folderId 对应的内容视图，过滤必须与 UI 一致；仅收藏视图不应用文件夹过滤。

不改 excludeFoldered 剔除逻辑（L879-885，保持 `_showFoldersView` 跳过）：folderId != null 时列表已被文件夹过滤，剔除无意义；folderId == null 的文件夹网格页不展示 meme 列表，避免影响文件夹卡片计数等旁路用途。

行为核对：文件夹 tab 内进入的文件夹（selectFolder 会置 `_showFoldersView=false`）过滤本来就生效；切走再切回文件夹 tab 后 `_showFoldersView=true` 但 folderId 仍在 → 修复后正确显示该文件夹内容（标题/返回箭头一致）；收藏 tab 不受影响；tab 0 仍会清 folderId（bbd8269 行为不变）。

## 修改 3：版本号

AGENTS.md `v1.0.6-dev` → `v1.0.7-dev`；pubspec.yaml version patch +1。

## 验证

1. `flutter analyze` 无错误警告（CI 门槛）。
2. 手动场景清单（实现后自述核对）：
   - 查看器：面板拖到最高 → 左右翻页再翻回 → 图片不再从面板下漏出；任意高度翻页 → 面板跳回 0.45 且图片区、遮罩、色块同帧贴合；面板拖到最低 0.2 → 底部无死区、可整体拖动；面板最高时空白区可下拉收起、横向滑动仍能切换图片；进出全屏后面板高度同步正常；IME 弹出后无错位。
   - 主页：tab 0 进入文件夹 X → 点文件夹 tab → 显示 X 的内容（标题为文件夹名、有返回箭头）→ 返回箭头回文件夹网格；收藏、搜索、标签过滤不受影响。
3. 不改测试（test/ 为空），跑一次 `flutter test` 确认无回归。