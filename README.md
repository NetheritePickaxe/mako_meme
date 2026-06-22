# Mako Meme 🐟

跨平台表情包管理器，基于 Flutter 构建，支持 **Android / Windows / Web**。

## 功能

- 📦 **表情包管理** — 创建、编辑、删除表情包包
- 🖼️ **批量导入** — 支持 PNG / GIF / WebP / JPEG 格式
- 🔍 **全局搜索** — 按标签和文件名搜索表情
- 🏷️ **标签系统** — 单个或批量编辑标签
- ✅ **批量选择** — 多选后批量删除、分享、打标签
- 🖥️ **桌面拖拽** — Windows/macOS/Linux 支持拖拽文件导入
- 📱 **瀑布流展示** — 自适应列数（3-6 列）
- 🌙 **暗色模式** — 跟随系统主题自动切换
- 🎭 **预置表情** — 首次启动自动生成 20 个示例表情

## CI/CD

项目使用 GitHub Actions 自动构建和发布。

| 触发事件 | 行为 |
|---|---|
| `push` main/master | 构建 Android APK + Web + Windows，部署 Web 到 Pages |
| `push` tag `v*` | 构建 + 自动创建 GitHub Release，附带所有产物 |
| `pull_request` | 仅运行静态分析 |

### 配置

使用前需在 GitHub 仓库设置以下 **Secrets / Settings**:

1. **`FEISHU_WEBHOOK_URL`** (可选) — 飞书机器人 Webhook 地址，用于接收构建结果通知
   - 在飞书群中添加自定义机器人 → 复制 webhook URL → 添加到仓库 Settings > Secrets > Actions
2. **GitHub Pages** (可选) — 启用自动部署：
   - Settings → Pages → Source 选择 **GitHub Actions**

### 发布流程

```bash
# 打标签即自动发布
git tag v1.0.0
git push origin v1.0.0
# → Actions 自动构建所有平台并创建 Release
```

## 技术栈

| 层 | 方案 |
|---|---|
| 状态管理 | flutter_riverpod |
| 本地数据库 | drift (SQLite) |
| 文件选择 | file_picker |
| 分享 | share_plus |
| 桌面拖拽 | desktop_drop |
| 瀑布流 | flutter_staggered_grid_view |
| 架构 | Clean Architecture (data/domain/presentation) |

## 快速开始

```bash
# 安装依赖
flutter pub get

# 生成 drift 代码（修改数据库后需要）
dart run build_runner build --delete-conflicting-outputs

# 运行
flutter run

# 构建 Web
flutter build web

# 构建 Windows
flutter build windows
```

## 项目结构

```
lib/
├── main.dart                  # 入口 + 预置数据初始化
├── app.dart                   # MaterialApp 配置
├── core/
│   └── theme.dart             # 主题 (Material 3)
├── data/
│   ├── database/
│   │   ├── tables.dart        # drift 表定义
│   │   └── database.dart      # 数据库操作
│   ├── repositories/
│   │   └── sticker_repository.dart
│   └── services/
│       ├── file_service.dart   # 文件存储
│       └── preset_service.dart # 预置表情生成
└── presentation/
    ├── providers/
    │   └── sticker_providers.dart
    ├── screens/
    │   ├── home_screen.dart
    │   └── pack_detail_screen.dart
    └── widgets/
        ├── sticker_preview.dart
        └── sticker_search_delegate.dart
```
