# Mako Meme

跨平台表情包管理器 (Android / Windows / Web)，Flutter + Provider + JSON 存储。

## Stack

- **Flutter** 3.29+ (CI: 3.44.2), SDK `>=3.10.3 <4.0.0`
- **State**: `ChangeNotifier` + `provider` (NOT Riverpod/Bloc). Call `notifyListeners()` after mutations.
- **Storage**: `StorageService` — JSON files on native, `localStorage` on web
- **No code gen**: No build_runner, drift, or freezed
- **Icons**: `flutter_launcher_icons` configured in pubspec.yaml (seed `#6366F1`)

## Entry

`lib/main.dart` → `MultiProvider` injects `MemeProvider` + `SettingsProvider` + `StorageService` + `AuthService` → `MakoMemeApp` → `HomeScreen`

## Providers

| Provider | Role |
|---|---|
| `MemeProvider` | Meme/folder CRUD, filtering (folder/mood/tag), fuzzy search (`fuzzy` package), multi-select, WebDAV sync |
| `SettingsProvider` | ThemeMode, Monet toggling, 15 color presets, custom colors, WebDAV config, user auth config |

## Architecture

```
lib/
├── main.dart
├── models/          meme.dart, folder.dart, mood.dart (toMap/fromMap/copyWith)
├── providers/       meme_provider.dart, settings_provider.dart
├── screens/         home_screen.dart, meme_viewer_screen.dart, settings_screen.dart
├── services/        storage_service.dart, webdav_service.dart, auth_service.dart,
│                    update_service.dart, storage_platform.dart (conditional export)
├── theme/           app_theme.dart (15 presets, Monet + custom color support)
└── widgets/         meme_card.dart, meme_grid.dart, folder_card.dart,
                     mako_search_bar.dart, multi_select_bar.dart
```

## Commands

| Action | Command |
|---|---|
| Get deps | `flutter pub get` |
| Analyze | `flutter analyze` (CI enforces `--no-fatal-infos`) |
| Build web | `flutter build web` |
| Build web (wasm) | `flutter build web --wasm` |
| Build Android | `flutter build apk --release` |
| Build Windows | `flutter build windows --release` |
| Serve web locally | `python -m http.server 58722 --directory build/web` |
| Serve web (WASM) | `python tools/serve_wasm.py 58722 build/web` |
| Run tests | `flutter test` (test/ is currently empty) |

## Conventions

- **Imports**: Use relative imports (`../models/...`), never `package:mako_meme/...`.
- **Models**: Immutable data classes with `copyWith()` and `toMap()`/`fromMap()`.
- **Platform branching**: Use `kIsWeb` from `flutter/foundation.dart` for web vs native; `Theme.of(context).platform` for desktop/mobile interaction.
- **Desktop/web detection** (`meme_card.dart:50-54`): `kIsWeb` OR Windows/Linux/macOS — **web counts as desktop**. Desktop offers drag, left-click copy, right-click context menu. Mobile offers click→viewer, long-press→share.
- **Drag & drop**: `desktop_drop` for OS file drops; `LongPressDraggable<Meme>` + `DragTarget<Meme>` for intra-app folder drag.
- **Naming**: Files `snake_case`, classes `PascalCase`.
- **Widget scope**: Screens in `screens/`, reusable widgets in `widgets/`.
- **Search**: Uses `fuzzy` package (Fuzzy with threshold 0.3). `#tag` prefix in search bar filters by tag substring.
- **ZIP export/import**: `archive` package — `StorageService.exportData()` / `StorageService.importZip()`.
- **WebDAV**: `WebDavService` with Basic auth; sync triggered via `MemeProvider.syncAllToWebDav()`.
- **GitHub Actions**: CI defined in `.github/workflows/build.yml`; gate `analyze` → build per platform (Android split-per-abi + Windows Inno Setup installer). Tag `v*` triggers auto Release. Feishu webhook (`FEISHU_WEBHOOK_URL` secret) for notifications.

## Storage

- **Native** (Android/Windows): Images copied to `{appDir}/mako_meme/memes/{uuid}.{ext}`. Metadata saved as `memes.json`. Persists across sessions.
- **Web**: Image bytes kept in-memory (`_webBytes` map). **Lost on page refresh**. Metadata (name/tags/folder/mood) saved to `localStorage`. Refresh shows metadata with "丢失 / 点击重导" placeholder — user can tap to re-import via file picker. No base64/blob persistence.
- **Duplicate filenames**: UUID-based filenames prevent file collision. `meme.name` stores original filename (without ext) which may duplicate across entries but that's allowed.
- **Import flow**: `FilePicker` → `PlatformFile` (native: path, web: bytes) → `StorageService.importFile()` → copies bytes + saves metadata → `MemeProvider.loadAll()` refreshes UI.
