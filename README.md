<p align="center">
  <img src="assets/icon_foreground.png" width="128" height="128" alt="Mako Meme">
</p>

<h1 align="center">Mako Meme 🌸</h1>

<p align="center">
  <b>跨平台表情包管理器</b><br>
  Android · Windows · Web
</p>

<p align="center">
  <a href="https://github.com/anomalyco/mako_meme/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/anomalyco/mako_meme/build.yml?style=flat-square" alt="Build">
  </a>
  <a href="https://github.com/anomalyco/mako_meme/releases">
    <img src="https://img.shields.io/github/v/release/anomalyco/mako_meme?style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/anomalyco/mako_meme/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License">
  </a>
</p>

<p align="center">
  <a href="https://netheritepickaxe.github.io/mako_meme/">
    <img src="https://img.shields.io/badge/在线体验-Web%20Demo-6366F1?style=for-the-badge" alt="Web Demo">
  </a>
</p>

---

## 📸 预览

```
[ 截图待补充 — Android / Windows / Web ]
```

## ✨ 功能

- **导入与管理** — 支持 PNG/GIF/WebP/JPEG，UUID 自动重命名防冲突
- **标签系统** — 自定义标签，搜索框输入 `#tag` 即可精确筛选
- **文件夹分组** — 拖拽归类（DragTarget），自由组织表情结构
- **心情标签** — 预设心情 + 自定义，图标化展示快速筛选
- **收藏系统** — 一键收藏，单独视图查看
- **全局搜索** — 名称 + 标签联合模糊搜索
- **批量操作** — 多选后批量删除、移动文件夹、修改心情
- **桌面拖拽导入** — Windows 原生文件拖拽（desktop_drop）
- **全屏查看器** — photo_view 支持双指缩放、分享、复制
- **Material You** — Monet 动态取色 + 多套预设主题色
- **暗色模式** — 跟随系统或手动切换
- **WebDAV 同步** — 跨设备元数据同步
- **图片缓存** — Hive 本地缓存加速

## 🛠️ 技术栈

| 类别     | 选型                                                             |
| -------- | ---------------------------------------------------------------- |
| 框架     | Flutter 3.29+ / Dart ^3.12.2                                     |
| 状态管理 | Provider (ChangeNotifier)                                        |
| 持久化   | JSON 文件 + Hive 缓存                                            |
| 同步     | WebDAV                                                           |
| 图片     | photo_view · mime · crypto                                       |
| 工具     | file_picker · share_plus · desktop_drop · uuid · fuzzy · archive |
| 主题     | dynamic_color (Monet)                                            |

## 🔐 管理员配置

Web 端支持管理员登录，首次启动会在项目根目录自动生成 `config.json`：

```json
{
  "admin": {
    "username": "",
    "password": ""
  }
}
```

- 编辑 `config.json` 填写管理员用户名和密码
- 密码在传输过程中以 SHA-256 哈希比对

### GitHub Actions 部署

| Secret名称 | 说明 |
|---|---|
| `ADMIN_USERNAME` | 管理员用户名 |
| `ADMIN_PASSWORD` | 管理员密码 |

## 🚀 快速上手

```bash
flutter pub get
flutter run                          # 开发运行
flutter build apk --release          # Android
flutter build windows --release      # Windows
flutter build web                    # Web
flutter analyze                      # 静态检查
flutter test                         # 测试
```

## 💾 存储说明

**Native** — 图片存 `{appDir}/mako_meme/memes/{uuid}.{ext}`，元数据存 JSON 文件，重启不丢。

**Web** — 元数据持久化到 `localStorage`，图片保留在运行内存中（刷新后丢失，显示占位符提示重新导入）。

## ⚖️ 免责声明

- 🌸 茉子（Mako）出自 Yuzusoft（柚子社）作品《千恋万花》。
- 🎨 应用图标来源于游戏素材解包，版权归 Yuzusoft 所有。
- 🤖 本项目为 AI 辅助开发的 vibecoding 作品。
