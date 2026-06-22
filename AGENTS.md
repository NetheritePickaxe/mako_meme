# Mako Meme

跨平台表情包管理器 (Android / Windows / Web)，Flutter + Provider + JSON 存储。

## Project

- **Stack**: Flutter 3.29+ (SDK ^3.12.2), `provider` (ChangeNotifier), `photo_view`, `file_picker`, `share_plus`, `desktop_drop`
- **Entry**: `lib/main.dart` → `MakoMemeApp` → `HomeScreen`
- **State**: `MemeProvider` (ChangeNotifier) injected via `MultiProvider` at root
- **Storage**: `StorageService` — JSON files on native, `localStorage` (base64) on web

## Commands

| Action | Command |
|---|---|
| Get deps | `cd mako_meme && flutter pub get` |
| Analyze | `cd mako_meme && flutter analyze` |
| Build web | `cd mako_meme && flutter build web` |
| Build web (wasm) | `cd mako_meme && flutter build web --wasm` |
| Build Android | `cd mako_meme && flutter build apk --release` |
| Build Windows | `cd mako_meme && flutter build windows --release` |
| Serve web locally | `cd mako_meme && python -m http.server 58722 --directory build/web` |
| Serve web (WASM) | `cd mako_meme && python tools/serve_wasm.py 58722 build/web` |
| Run tests | `cd mako_meme && flutter test` |

## Architecture

```
lib/
├── main.dart                    # Entry — Provider + MaterialApp
├── models/                      # Data classes
│   ├── meme.dart                # Meme (image/text/emoji, tags, mood, favorite)
│   ├── folder.dart              # MemeFolder (grouping)
│   └── mood.dart                # MemeMood + presetMoods + iconName→IconData map
├── providers/
│   └── meme_provider.dart       # MemeProvider: all state + filtering + CRUD
├── screens/
│   ├── home_screen.dart         # Main screen: AppBar + Drawer + search + mixed grid
│   └── meme_viewer_screen.dart  # Full-screen viewer with share/copy/mood/fav
├── services/
│   └── storage_service.dart     # JSON persistence (native File / web localStorage)
├── theme/
│   └── app_theme.dart           # light + dark ThemeData (Material 3, seed #6366F1)
└── widgets/
    ├── meme_card.dart           # Meme thumbnail + desktop/mobile click logic
    ├── meme_grid.dart           # Responsive grid (2–8 cols)
    ├── folder_card.dart         # Folder thumbnail + DragTarget for meme drops
    ├── mako_search_bar.dart     # Search TextField with #prefix tag search
    ├── multi_select_bar.dart    # Batch action bar (delete/move/mood)
    └── folder_card.dart         # Folder card with DragTarget<Meme> receiver
```

## Conventions

- **State**: `ChangeNotifier` + `provider` (NOT Riverpod / Bloc). Call `notifyListeners()` after mutations.
- **Models**: Immutable data classes with `copyWith()` and `toMap()`/`fromMap()` for JSON serialization.
- **Imports**: Use relative imports (`../models/...`), never `package:mako_meme/...`.
- **Platform branching**: Use `kIsWeb` from `flutter/foundation.dart` for web vs native; `Theme.of(context).platform` for desktop/mobile interaction.
- **Desktop vs Mobile**: Desktop=Win/Linux/macOS — left-click copy, right-click menu; Mobile=click→viewer, long-press→share.
- **Drag & drop**: `desktop_drop` package for OS file drops; `LongPressDraggable<Meme>` + `DragTarget<Meme>` for intra-app drag.
- **Naming**: Files use `snake_case`, classes `PascalCase`.
- **Widget scope**: Screens in `screens/`, reusable widgets in `widgets/`.
- **No code gen**: No build_runner, no drift, no freezed.
- **GitHub Actions**: CI defined in `.github/workflows/build.yml`; `flutter analyze` gate, then build per platform. No `build_runner` step.

## Notes

-
