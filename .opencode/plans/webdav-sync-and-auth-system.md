# WebDAV 同步 + 用户权限系统实施方案

## 目标
为 Mako Meme 所有平台添加 WebDAV 同步功能，支持：
1. 图片持久化存储到 WebDAV 服务器（如 OpenList）
2. 跨设备同步，刷新不丢失
3. Web 端支持公共/私有两种模式
4. 所有平台统一实现

## 架构设计

### 核心组件
```
┌─────────────────────────────────────────────────────────────┐
│                       客户端 (Flutter)                        │
├─────────────────────────────────────────────────────────────┤
│  MemeProvider (状态管理)                                      │
│  ├── 过滤逻辑: filterByUser() / filterPublic()               │
│  └── 加载逻辑: loadFromLocal() / loadFromWebDav()            │
├─────────────────────────────────────────────────────────────┤
│  WebDavService (文件存储)                                     │
│  ├── uploadFile() / downloadFile()                           │
│  └── listRemote() / deleteRemote()                           │
├─────────────────────────────────────────────────────────────┤
│  AuthService (用户认证)                                       │
│  ├── login() / logout() / register()                         │
│  └── getCurrentUser()                                        │
├─────────────────────────────────────────────────────────────┤
│  StorageService (本地持久化)                                   │
│  ├── saveMemeMetadata() / loadMemeMetadata()                 │
│  └── saveLocalCache() / loadLocalCache()                     │
└─────────────────────────────────────────────────────────────┘
```

### 数据模型变更

**Meme 模型新增字段**：
```dart
class Meme {
  String id;
  String name;
  String type; // 'image' | 'text' | 'emoji'
  String? remotePath;       // WebDAV 远程路径
  String? localCachePath;   // 本地缓存路径
  String? userId;           // 所属用户 ID (null = 公共)
  List<String> tags;
  String? folderId;
  String? mood;
  bool isFavorite;
}
```

**Settings 新增字段**：
```dart
class Settings {
  bool useWebDav;
  String? webDavBaseUrl;
  String? webDavUsername;
  String? webDavPassword;
  String? webDavToken;
  bool useUserAuth;  // 是否启用用户认证
  String? currentUserId;
}
```

## 实现步骤

### 第一阶段：基础 WebDAV 服务
1. 添加 `webdav_client` 依赖到 pubspec.yaml
2. 创建 `lib/services/webdav_service.dart`
   - 实现上传文件到 WebDAV
   - 实现从 WebDAV 下载文件
   - 实现列出远程目录
   - 实现删除远程文件
   - 实现连接测试
3. 在 SettingsScreen 添加 WebDAV 配置 UI

### 第二阶段：用户认证系统
1. 创建 `lib/services/auth_service.dart`
   - 实现登录/登出/注册功能
   - 实现获取当前用户
2. 在 SettingsScreen 添加用户认证配置 UI
3. 在 HomeScreen 添加用户切换 UI（公共/私有模式切换）

### 第三阶段：集成到 MemeProvider
1. 修改 `MemeProvider` 支持 WebDAV 同步
   - 添加 WebDAV 同步方法
   - 修改导入逻辑：上传到 WebDAV + 保存到本地缓存
   - 修改加载逻辑：优先本地缓存，无缓存则从 WebDAV 下载
2. 修改 `Meme` 模型添加 `userId` 和 `remotePath` 字段
3. 修改 `StorageService` 支持本地缓存和 WebDAV 存储
   - 添加保存/加载本地缓存方法
   - 添加保存/加载远程路径方法

### 第四阶段：跨平台适配和安全优化
1. 适配 Android/Windows/Web 平台
   - Android: 使用 `webdav_client` 包
   - Windows: 使用 `http` 包实现 WebDAV 协议
   - Web: 使用 `http` 包 + CORS 配置
2. 添加密码加密存储
   - 使用 `flutter_secure_storage` 或加密算法
3. 实现后台同步
   - 检测网络变化时自动同步
   - 或提供手动同步按钮
4. 添加冲突解决机制
   - 处理同名文件冲突
   - 处理不同步导致的版本冲突

## 需要的依赖

```yaml
dependencies:
  webdav_client: ^1.0.0  # WebDAV 客户端
  crypto: ^3.0.0         # 密码哈希
  flutter_secure_storage: ^8.0.0  # 安全存储
  
dev_dependencies:
  # 现有依赖保持不变
```

## 安全考虑

1. **密码加密**：使用 `crypto` 包对密码进行哈希存储
2. **HTTPS 强制**：WebDAV 连接必须使用 HTTPS
3. **令牌刷新**：支持 OAuth 2.0 刷新令牌
4. **本地缓存清理**：提供清除本地缓存的选项

## 用户体验流程

```
用户导入图片
    ↓
检查是否有 WebDAV 配置
    ↓
有配置 → 上传到 WebDAV + 保存到本地缓存
    ↓
无配置 → 只保存到本地
    ↓
下次启动
    ↓
检查本地缓存
    ↓
有缓存 → 直接显示
    ↓
无缓存 → 从 WebDAV 下载
    ↓
根据用户权限过滤
    ↓
显示公共图片或私人图片
```

## 修改文件清单

1. `pubspec.yaml` - 添加 `webdav_client` 依赖
2. `lib/services/webdav_service.dart` - 新建 WebDAV 服务
3. `lib/services/auth_service.dart` - 新建用户认证服务
4. `lib/services/storage_service.dart` - 修改存储逻辑
5. `lib/providers/settings_provider.dart` - 添加 WebDAV 配置
6. `lib/providers/meme_provider.dart` - 添加 WebDAV 同步逻辑
7. `lib/screens/settings_screen.dart` - 添加 WebDAV 和用户认证设置 UI
8. `lib/screens/home_screen.dart` - 添加用户切换 UI
9. `lib/models/meme.dart` - 添加远程路径和用户 ID 字段
10. `lib/main.dart` - 初始化 WebDAV 服务和用户认证服务

## 注意事项

1. WebDAV 服务器需要支持 CORS（Web 端）
2. 图片大小限制需要考虑（WebDAV 服务器可能有文件大小限制）
3. 网络不稳定时需要提供重试机制
4. 用户权限切换时需要重新加载数据
