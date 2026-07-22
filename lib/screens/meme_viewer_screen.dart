import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../models/meme.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/settings_provider.dart';
import '../l10n/l10n.dart';
import '../services/storage_service.dart';
import '../services/pdf_opener.dart';
import 'text_editor_screen.dart';
import 'character_card_editor_screen.dart';
import '../utils/lru_cache.dart';

/// 是否为移动平台
bool _isMobilePlatform() {
  if (kIsWeb) return false;
  final p = defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

class MemeViewerScreen extends StatefulWidget {
  final List<Meme> memes;
  final int initialIndex;
  const MemeViewerScreen({super.key, required this.memes, required this.initialIndex});

  @override
  State<MemeViewerScreen> createState() => _MemeViewerScreenState();
}

class _MemeViewerScreenState extends State<MemeViewerScreen> {
  late PageController _controller;
  late int _currentIndex;
  // LRU 缓存：最多保留 3 项，避免来回滑动时内存累积导致 OOM
  final LruCache<int, Uint8List?> _bytesCache = LruCache(3);
  final LruCache<int, File?> _fileCache = LruCache(3);

  // 详情面板当前占据屏幕高度的比例（0.0~1.0）
  // 拖动面板时实时更新，图片区域随之收缩，保证图片始终可见
  double _panelExtent = 0.45;

  // 全屏查看模式：隐藏 AppBar 和详情面板，图片占满整屏
  // 单击图片切换，支持 PhotoView/InteractiveViewer 捏合缩放
  bool _isFullscreen = false;

  // 角色卡预览展开/收起状态：默认收起，避免长内容撑爆详情面板
  bool _cardExpanded = false;

  // 详情面板回顶按钮
  bool _showScrollToTop = false;
  ScrollController? _lastDetailController;

  void _onDetailScroll() {
    final offset = _lastDetailController?.offset ?? 0;
    final show = _cardExpanded && offset > 600;
    if (show != _showScrollToTop) {
      setState(() => _showScrollToTop = show);
    }
  }

  // 漫画内部页面滑动
  int _mangaPageIndex = 0;
  final LruCache<String, Uint8List?> _mangaBytesCache = LruCache(3);
  final LruCache<String, File?> _mangaFileCache = LruCache(3);

  // 立绘/CG 精灵图层可见性状态：memeId -> {layerZOrder: visible}
  // 用户切换图层面板后覆盖默认 visible
  final Map<String, Map<int, bool>> _spriteVisibility = {};
  // 立绘/CG 图层字节缓存：layerPath -> bytes（web）/ File（native 已用 path 直接读）
  final LruCache<String, Uint8List?> _spriteBytesCache = LruCache(8);

  // 序列帧
  int _currentSpriteFrame = 0;
  ui.Image? _ssImage;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  /// 当前 meme：优先从 provider 读取最新数据（标签/名称等变更后立即刷新）
  /// 若列表已变化导致索引越界，则回退到 widget 传入的快照
  Meme get _meme {
    final liveList = context.read<MemeProvider>().memes;
    if (_currentIndex >= 0 && _currentIndex < liveList.length) {
      return liveList[_currentIndex];
    }
    if (_currentIndex >= 0 && _currentIndex < widget.memes.length) {
      return widget.memes[_currentIndex];
    }
    return widget.memes.first;
  }

  /// 切换全屏查看模式：单击图片进入/退出全屏
  /// 进入全屏时隐藏系统状态栏，退出时恢复
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      // 进入沉浸式全屏：隐藏状态栏和导航栏，图片真正占满整屏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // 退出全屏：恢复边到边模式（状态栏可见）
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    // 退出页面时若仍处于全屏，恢复系统 UI 模式
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller.dispose();
    super.dispose();
  }

  /// 全屏查看时的 cacheWidth：按屏幕短边 × devicePixelRatio 计算，上限 4096
  /// 这样既保证清晰度，又避免超大图全分辨率解码导致 OOM
  int get _viewerCacheWidth {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final shortSide = size.shortestSide;
    final target = (shortSide * dpr).round();
    return target > 4096 ? 4096 : target;
  }

  /// 实际显示路径：有缩略图（PSD/ICO/TIF）时用 thumbPath，否则用 filePath
  String _displayPath(Meme m) => m.displayPath;

  Future<void> _ensureBytes(int index) async {
    if (_bytesCache.containsKey(index) || _fileCache.containsKey(index)) return;
    final m = widget.memes[index];
    // PDF 不需要加载图片字节（显示图标 + 外部打开）
    if (m.isPdf) {
      _bytesCache.put(index, null);
      return;
    }
    final path = _displayPath(m);
    if (!m.isImageType || path.isEmpty) {
      _bytesCache.put(index, null);
      return;
    }
    try {
      final storage = context.read<StorageService>();
      if (kIsWeb) {
        final b = await storage.readMemeBytes(path);
        if (mounted) setState(() => _bytesCache.put(index, b));
      } else {
        // 原生端：同步设置 File，靠 PhotoView/Image 的 errorBuilder 兜底
        // 这样首次 build 就能命中 Flutter ImageCache，避免加载等待
        final f = storage.getMemeFile(path);
        _fileCache.put(index, f);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<MemeProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;

    return PopScope(
      // 全屏模式下按返回键先退出全屏，而非直接 pop
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          _toggleFullscreen();
        } else if (didPop) {
          // 真正退出页面时恢复系统 UI 模式
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        // 全屏模式隐藏 AppBar，图片占满整屏
        appBar: _isFullscreen ? null : AppBar(
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.tr('back'),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _meme.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _meme.isManga
                    ? '${_currentIndex + 1} / ${widget.memes.length}  ·  ${l10n.tr('manga_page_label')} ${_mangaPageIndex + 1} / ${_meme.pages.length}'
                    : _meme.isSpriteSheet && _meme.spriteSheet != null
                        ? '${_currentIndex + 1} / ${widget.memes.length}  ·  ${l10n.tr('sprite_sheet_frame_label')} ${_currentSpriteFrame + 1} / ${_meme.spriteSheet!['frameCount']}'
                        : '${_currentIndex + 1} / ${widget.memes.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          actions: [
            // PSD 图层面板按钮
            if (_meme.isPsd)
              IconButton(
                icon: const Icon(Icons.layers),
                tooltip: l10n.tr('psd_layers'),
                onPressed: () => _showPsdLayersPanel(_meme, l10n),
              ),
            // 立绘/CG 精灵图层面板按钮
            if (_meme.isSprite)
              IconButton(
                icon: const Icon(Icons.face_retouching_natural),
                tooltip: l10n.tr('sprite_layers'),
                onPressed: () => _showSpriteLayersPanel(_meme, l10n),
              ),
          ],
        ),
        body: PageView.builder(
          // 全屏模式下禁用左右滑动，避免与 PhotoView 捏合缩放冲突
          // 非全屏保持 BouncingScrollPhysics，允许左右切换上一张/下一张
          physics: _isFullscreen
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          controller: _controller,
          // 使用 provider 的实时列表，标签/名称变更后立即刷新
          itemCount: prov.memes.length,
          onPageChanged: (i) => setState(() {
            _currentIndex = i;
            _mangaPageIndex = 0;
          }),
          itemBuilder: (ctx, i) {
            final m = prov.memes[i];
            final screenHeight = MediaQuery.sizeOf(context).height;
            // 全屏模式下面板高度为 0，图片占满；否则留出面板高度
            final panelHeight = _isFullscreen ? 0.0 : _panelExtent * screenHeight;
            // 使用 Stack 让面板覆盖在图片上方，避免 Column 无界高度导致 DraggableScrollableSheet 失效
            // Align(bottomCenter) 让面板固定在底部并可正确计算高度
            return NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                final newExtent = notification.extent;
                if ((newExtent - _panelExtent).abs() > 0.005) {
                  setState(() => _panelExtent = newExtent);
                }
                return false;
              },
              child: Stack(
                children: [
                  // ClipRect 强制裁剪，防止超大画幅图片在 PhotoView 缩放时
                  // 溢出到 PageView 相邻页面（左右两侧看到本页内容）
                  Positioned.fill(
                    bottom: panelHeight,
                    child: ClipRect(
                      child: GestureDetector(
                        onTap: _toggleFullscreen,
                        behavior: HitTestBehavior.translucent,
                        child: _buildImageArea(m, i),
                      ),
                    ),
                  ),
                  if (!_isFullscreen)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildDraggableDetailPanel(theme, prov, m, l10n),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 图片展示区
  /// - SVG: SvgPicture + InteractiveViewer（矢量无限缩放）
  /// - GIF/APNG: Image + InteractiveViewer（保持动画播放）
  /// - PSD: 显示合成预览（thumbPath）
  /// - 漫画: PageView 内部滑动 + PhotoView 单页缩放
  /// - 普通位图: PhotoView（支持手势缩放）
  Widget _buildImageArea(Meme m, int i) {
    final theme = Theme.of(context);

    // 漫画：内置 PageView 滑动多页
    if (m.isManga) {
      return _buildMangaReader(theme, m);
    }

    _ensureBytes(i);
    final bytes = _bytesCache.get(i);
    final file = _fileCache.get(i);
    final hasData = bytes != null || file != null;

    // PDF：显示文档图标 + 文件信息 + 外部打开按钮
    if (m.isPdf) {
      return _buildPdfView(theme, m);
    }

    // 立绘/CG 精灵图层合成视图
    if (m.isSprite) {
      return _buildSpriteView(theme, m);
    }

    // 序列帧视图
    if (m.isSpriteSheet) {
      return _buildSpriteSheetView(theme, m);
    }

    if (m.isImageType && m.displayPath.isNotEmpty) {
      if (!hasData) {
        return Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        );
      }

      // SVG 矢量图：无限缩放不失真
      if (m.isVector) {
        final svgBytes = bytes ?? file?.readAsBytesSync();
        return Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 8.0,
            child: svgBytes != null
                ? SvgPicture.memory(svgBytes, fit: BoxFit.contain,
                    placeholderBuilder: (_) => _loadingIndicator(theme))
                : _loadingIndicator(theme),
          ),
        );
      }

      // GIF / APNG 动图：保持动画播放，加 cacheWidth 避免多帧 OOM
      if (m.isAnimated) {
        final cw = _viewerCacheWidth;
        return Center(
          child: InteractiveViewer(
            child: file != null
                ? Image.file(file, fit: BoxFit.contain, cacheWidth: cw)
                : Image.memory(bytes!, fit: BoxFit.contain, cacheWidth: cw),
          ),
        );
      }

      // PSD / 普通位图：用 PhotoView 手势缩放
      // 用 ResizeImage 包装，解码时缩放到目标宽度，避免超大图（如 2GB）全分辨率解码导致 OOM
      // 目标宽度 = 屏幕长边 × dpr × 2（留出 2x 放大余量），上限 4096
      final viewSize = MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final targetWidth = (viewSize.longestSide * dpr * 2).round().clamp(1024, 4096);
      final ImageProvider baseProvider = file != null
          ? FileImage(file)
          : MemoryImage(bytes!);
      final resizedProvider = ResizeImage(baseProvider, width: targetWidth);
      return PhotoView(
        imageProvider: resizedProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        heroAttributes: PhotoViewHeroAttributes(tag: m.id),
        backgroundDecoration: BoxDecoration(color: theme.colorScheme.surface),
        loadingBuilder: (_, event) => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
            value: event == null ? null : event.cumulativeBytesLoaded /
                (event.expectedTotalBytes ?? 1),
          ),
        ),
        errorBuilder: (_, error, ___) => _errorWidget(theme, error),
      );
    }

    // 小说：可滚动的长文阅读器，支持 Markdown 渲染
    if (m.isNovel || m.isMd) {
      return _buildNovelReader(theme, m);
    }

    // 文字表情居中显示
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          m.textContent ?? '',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 漫画阅读器：内置 PageView，左右滑动切换页面
  /// 单页使用 PhotoView 支持手势缩放
  Widget _buildMangaReader(ThemeData theme, Meme m) {
    final l10n = context.read<LocaleProvider>().l10n;
    final pages = m.pages;
    if (pages.isEmpty) {
      return Center(
        child: Text(l10n.tr('manga_no_pages'), style: theme.textTheme.bodyLarge),
      );
    }
    return PageView.builder(
      itemCount: pages.length,
      onPageChanged: (i) => setState(() => _mangaPageIndex = i),
      itemBuilder: (ctx, pageIdx) {
        final pagePath = pages[pageIdx];
        _ensureMangaPageBytes(pagePath);
        final bytes = _mangaBytesCache.get(pagePath);
        final file = _mangaFileCache.get(pagePath);

        if (bytes == null && file == null) {
          return Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
          );
        }

        return Stack(
          children: [
            PhotoView(
              // 用 ResizeImage 限制解码尺寸，避免超大图 OOM
              imageProvider: ResizeImage(
                file != null ? FileImage(file) : MemoryImage(bytes!),
                width: _viewerCacheWidth,
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              backgroundDecoration: BoxDecoration(color: theme.colorScheme.surface),
              loadingBuilder: (_, event) => Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                  value: event == null ? null : event.cumulativeBytesLoaded /
                      (event.expectedTotalBytes ?? 1),
                ),
              ),
              errorBuilder: (_, error, ___) => _errorWidget(theme, error),
            ),
            // 右下角页码指示器
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pageIdx + 1} / ${pages.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 加载漫画单页字节（按页面路径缓存）
  Future<void> _ensureMangaPageBytes(String pagePath) async {
    if (_mangaBytesCache.containsKey(pagePath) || _mangaFileCache.containsKey(pagePath)) return;
    if (pagePath.isEmpty) {
      _mangaBytesCache.put(pagePath, null);
      return;
    }
    try {
      final storage = context.read<StorageService>();
      if (kIsWeb) {
        final b = await storage.readMemeBytes(pagePath);
        if (mounted) setState(() => _mangaBytesCache.put(pagePath, b));
      } else {
        final f = storage.getMemeFile(pagePath);
        final exists = f != null && await f.exists();
        if (mounted) setState(() => _mangaFileCache.put(pagePath, exists ? f : null));
      }
    } catch (_) {}
  }

  /// 小说阅读器：可滚动，支持 Markdown 段落渲染
  Widget _buildNovelReader(ThemeData theme, Meme m) {
    final l10n = context.read<LocaleProvider>().l10n;
    final content = m.textContent ?? '';
    if (content.isEmpty) {
      return Center(child: Text(l10n.tr('no_text_content'), style: theme.textTheme.bodyLarge));
    }
    final lines = content.split('\n');
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.asMap().entries.map((e) {
          final line = e.value;
          final ts = theme.textTheme;
          if (line.startsWith('# ')) {
            return Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: Text(line.substring(2), style: ts.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            );
          }
          if (line.startsWith('## ')) {
            return Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: Text(line.substring(3), style: ts.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            );
          }
          if (line.startsWith('### ')) {
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(line.substring(4), style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            );
          }
          if (line.trim() == '---' || line.trim() == '***') {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: theme.colorScheme.outlineVariant),
            );
          }
          if (line.startsWith('> ')) {
            return Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
                ),
                padding: const EdgeInsets.only(left: 12),
                child: Text(line.substring(2), style: ts.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic, height: 1.8)),
              ),
            );
          }
          if (line.trim().isEmpty) return const SizedBox(height: 12);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(line, style: ts.bodyLarge?.copyWith(height: 1.8)),
          );
        }).toList(),
      ),
    );
  }

  Widget _loadingIndicator(ThemeData theme) => Center(
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: theme.colorScheme.primary,
    ),
  );

  Widget _errorWidget(ThemeData theme, Object? error) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 8),
        Text(
          '图片加载失败',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      ],
    ),
  );

  /// PDF 查看器：显示封面缩略图（若有）+ 文件信息 + 外部打开按钮
  /// 不内置完整 PDF 渲染引擎以避免包体过大，封面用 pdfx 渲染第一页
  Widget _buildPdfView(ThemeData theme, Meme m) {
    final l10n = context.read<LocaleProvider>().l10n;
    final storage = context.read<StorageService>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 封面：有 thumbPath 显示渲染的封面，否则显示 PDF 图标
            if (m.thumbPath != null && m.thumbPath!.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                child: kIsWeb
                    ? FutureBuilder<Uint8List?>(
                        future: storage.readMemeBytes(m.thumbPath!),
                        builder: (ctx, snap) {
                          if (snap.data == null) {
                            return Icon(Icons.picture_as_pdf, size: 80,
                                color: theme.colorScheme.primary);
                          }
                          return InteractiveViewer(
                            child: Image.memory(snap.data!, fit: BoxFit.contain),
                          );
                        },
                      )
                    : FutureBuilder<File?>(
                        future: Future.value(storage.getMemeFile(m.thumbPath!)),
                        builder: (ctx, snap) {
                          if (snap.data == null || !snap.data!.existsSync()) {
                            return Icon(Icons.picture_as_pdf, size: 80,
                                color: theme.colorScheme.primary);
                          }
                          return InteractiveViewer(
                            child: Image.file(snap.data!, fit: BoxFit.contain),
                          );
                        },
                      ),
              )
            else
              Icon(Icons.picture_as_pdf, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              m.name,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${m.extension.toUpperCase()} · ${m.fileSize > 0 ? '${(m.fileSize / 1024).toStringAsFixed(0)} KB' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            if (!kIsWeb)
              FilledButton.icon(
                onPressed: () => _openPdfExternally(m),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.tr('open_externally')),
              ),
            if (kIsWeb)
              FilledButton.icon(
                onPressed: () => _openPdfInBrowser(m),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.tr('open_in_new_tab')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPdfExternally(Meme m) async {
    final storage = context.read<StorageService>();
    final file = storage.getMemeFile(m.filePath);
    if (file == null || !await file.exists()) return;
    // Android/iOS：file:// URI 因 scoped storage + FileProvider 限制，launchUrl 通常无效
    // 改用系统分享菜单（Share sheet），让用户选择 PDF 阅读器打开
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: '${m.name}.pdf')],
      );
      return;
    }
    // 桌面端（Windows/macOS/linux）：用系统默认应用打开
    final uri = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Web 端：读取 PDF 字节并用浏览器新标签页打开预览
  Future<void> _openPdfInBrowser(Meme m) async {
    final storage = context.read<StorageService>();
    final l10n = context.read<LocaleProvider>().l10n;
    final bytes = await storage.readMemeBytes(m.filePath);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('pdf_web_hint'))),
      );
      return;
    }
    final ok = await openPdfInNewTab(bytes, m.name);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('pdf_web_hint'))),
      );
    }
  }

  /// PSD 图层面板
  void _showPsdLayersPanel(Meme m, L10n l10n) {
    final theme = Theme.of(context);
    final layers = m.psdLayers ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, controller) => Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.layers, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.tr('psd_layers')} (${layers.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${m.width}×${m.height}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (layers.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.tr('psd_no_layers'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: layers.length,
                      itemBuilder: (ctx, i) {
                        final layer = layers[i];
                        final name = layer['name'] as String? ?? '';
                        final visible = layer['visible'] as bool? ?? true;
                        final left = layer['left'] as int? ?? 0;
                        final top = layer['top'] as int? ?? 0;
                        final w = layer['width'] as int? ?? 0;
                        final h = layer['height'] as int? ?? 0;
                        final depth = layer['depth'] as int? ?? 0;
                        final hasImage = layer['hasImage'] as bool? ?? false;

                        return ListTile(
                          leading: Padding(
                            padding: EdgeInsets.only(left: depth * 12.0),
                            child: Icon(
                              hasImage ? Icons.image : Icons.folder_outlined,
                              size: 20,
                              color: hasImage
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              color: visible
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          subtitle: hasImage
                              ? Text(
                                  '$w×$h @ ($left,$top)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          trailing: Icon(
                            visible ? Icons.visibility : Icons.visibility_off,
                            size: 18,
                            color: visible
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 立绘/CG 精灵图层合成视图
  /// 按可见性叠加所有 visible 图层，支持 InteractiveViewer 缩放
  Widget _buildSpriteView(ThemeData theme, Meme m) {
    final layers = m.spriteLayers ?? [];
    if (layers.isEmpty) {
      return Center(child: Text(_tr('sprite_no_layers'),
        style: theme.textTheme.bodyMedium));
    }

    // 获取当前可见性（用户覆盖优先，否则用图层默认 visible）
    final visibilityOverrides = _spriteVisibility[m.id] ?? {};
    final visibleLayers = layers.where((l) {
      final zOrder = (l['zOrder'] as num?)?.toInt() ?? 0;
      return visibilityOverrides.containsKey(zOrder)
          ? visibilityOverrides[zOrder]!
          : (l['visible'] as bool? ?? false);
    }).toList()
      ..sort((a, b) {
        final za = (a['zOrder'] as num?)?.toInt() ?? 0;
        final zb = (b['zOrder'] as num?)?.toInt() ?? 0;
        return za.compareTo(zb);
      });

    if (visibleLayers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(_tr('sprite_no_visible_layer'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return Center(
      child: InteractiveViewer(
        minScale: 0.3,
        maxScale: 4.0,
        child: Stack(
          alignment: Alignment.center,
          children: visibleLayers.map((layer) {
            final path = layer['path'] as String? ?? '';
            return _buildSpriteLayerImage(theme, path);
          }).toList(),
        ),
      ),
    );
  }

  /// 构建单层精灵图层图片
  Widget _buildSpriteLayerImage(ThemeData theme, String path) {
    if (kIsWeb) {
      return FutureBuilder<Uint8List?>(
        future: _loadSpriteBytes(path),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              width: 200, height: 200,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (snap.data == null) return const SizedBox.shrink();
          return Image.memory(snap.data!, fit: BoxFit.contain);
        },
      );
    }
    final storage = context.read<StorageService>();
    final f = storage.getMemeFile(path);
    if (f == null) return const SizedBox.shrink();
    return Image.file(f, fit: BoxFit.contain);
  }

  Future<Uint8List?> _loadSpriteBytes(String path) async {
    final cached = _spriteBytesCache.get(path);
    if (cached != null) return cached;
    final storage = context.read<StorageService>();
    final b = await storage.readMemeBytes(path);
    _spriteBytesCache.put(path, b);
    return b;
  }

  /// 加载序列帧原图并解码为 ui.Image
  Future<void> _loadSpriteSheetImage(Meme m) async {
    if (_ssImage != null) return;
    final storage = context.read<StorageService>();
    try {
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = await storage.readMemeBytes(m.displayPath);
      } else {
        final file = storage.getMemeFile(m.displayPath);
        if (file != null) bytes = await file.readAsBytes();
      }
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _ssImage = frame.image);
    } catch (_) {}
  }

  /// 序列帧查看器
  Widget _buildSpriteSheetView(ThemeData theme, Meme m) {
    final ss = m.spriteSheet;
    if (ss == null) {
      return Center(child: Text('No sprite sheet data',
        style: theme.textTheme.bodyMedium));
    }
    final cols = ss['cols'] as int;
    final rows = ss['rows'] as int;
    final frameW = ss['frameWidth'] as int;
    final frameH = ss['frameHeight'] as int;
    final frameCount = ss['frameCount'] as int;
    final l10n = context.read<LocaleProvider>().l10n;

    _loadSpriteSheetImage(m);

    if (_ssImage == null) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 8.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _FramePainter(
                    image: _ssImage!,
                    frameIndex: _currentSpriteFrame,
                    cols: cols,
                    rows: rows,
                  ),
                  size: Size(frameW.toDouble(), frameH.toDouble()),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _currentSpriteFrame > 0
                    ? () => setState(() => _currentSpriteFrame--)
                    : null,
                tooltip: l10n.tr('previous'),
              ),
              Text(
                '${_currentSpriteFrame + 1} / $frameCount',
                style: theme.textTheme.titleSmall,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: _currentSpriteFrame < frameCount - 1
                    ? () => setState(() => _currentSpriteFrame++)
                    : null,
                tooltip: l10n.tr('next'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 立绘/CG 图层面板：可切换差分可见性
  void _showSpriteLayersPanel(Meme m, L10n l10n) {
    final theme = Theme.of(context);
    final layers = List<Map<String, dynamic>>.from(m.spriteLayers ?? []);
    // 按类别分组
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final l in layers) {
      final cat = (l['category'] as String?) ?? 'expression';
      grouped.putIfAbsent(cat, () => []).add(l);
    }
    // 类别排序：base > expression > outfit > accessory > other
    const catOrder = ['base', 'expression', 'outfit', 'accessory'];
    final sortedCats = grouped.keys.toList()
      ..sort((a, b) {
        final ia = catOrder.indexOf(a);
        final ib = catOrder.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    // 初始化覆盖状态
    if (!_spriteVisibility.containsKey(m.id)) {
      _spriteVisibility[m.id] = {
        for (final l in layers)
          ((l['zOrder'] as num?)?.toInt() ?? 0): (l['visible'] as bool? ?? false),
      };
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.25,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, controller) => Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.face_retouching_natural,
                            color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${l10n.tr('sprite_layers')} (${layers.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: Text(l10n.tr('sprite_reset')),
                            onPressed: () {
                              setState(() {
                                _spriteVisibility[m.id] = {
                                  for (final l in layers)
                                    ((l['zOrder'] as num?)?.toInt() ?? 0):
                                        (l['visible'] as bool? ?? false),
                                };
                              });
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.only(bottom: 16),
                        children: sortedCats.map((cat) {
                          final catLayers = grouped[cat]!;
                          return _buildSpriteCategorySection(
                            theme, l10n, m, cat, catLayers, setSheetState,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 立绘/CG 图层面板：单个类别分区
  Widget _buildSpriteCategorySection(
    ThemeData theme,
    L10n l10n,
    Meme m,
    String category,
    List<Map<String, dynamic>> layers,
    void Function(void Function()) setSheetState,
  ) {
    final catLabel = {
      'base': l10n.tr('sprite_cat_base'),
      'expression': l10n.tr('sprite_cat_expression'),
      'outfit': l10n.tr('sprite_cat_outfit'),
      'accessory': l10n.tr('sprite_cat_accessory'),
    }[category] ?? category;

    final overrides = _spriteVisibility[m.id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            catLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (final layer in layers)
          SwitchListTile(
            secondary: Icon(
              category == 'base' ? Icons.person : Icons.layers,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(layer['name'] as String? ?? ''),
            value: overrides[(layer['zOrder'] as num?)?.toInt() ?? 0] ?? false,
            onChanged: (v) {
              final z = (layer['zOrder'] as num?)?.toInt() ?? 0;
              setState(() => _spriteVisibility[m.id]![z] = v);
              setSheetState(() {});
            },
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  /// 简化的 tr 调用（避免在 _buildSpriteView 中重复获取 l10n）
  String _tr(String key) => context.read<LocaleProvider>().l10n.tr(key);

  /// 底部详情面板：可拖动展开/收起
  Widget _buildDraggableDetailPanel(ThemeData theme, MemeProvider prov, Meme m, L10n l10n) {
    final isMobile = _isMobilePlatform();
    final settings = context.watch<SettingsProvider>();
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.2,
      maxChildSize: 1.0,
      builder: (ctx, controller) {
        if (controller != _lastDetailController) {
          _lastDetailController?.removeListener(_onDetailScroll);
          _lastDetailController = controller;
          controller.addListener(_onDetailScroll);
        }
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // 手势指示条（可拖动）
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 名称（纯展示，重命名按钮在底部操作区）
                Text(
                  m.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // 文件信息
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _infoChip(theme, _typeLabel(m.type, l10n), icon: _typeIcon(m.type), accent: theme.colorScheme.secondary),
                    _infoChip(theme, _formatFileSize(m.fileSize), icon: Icons.data_usage),
                    if (m.width > 0 && m.height > 0)
                      _infoChip(theme, '${m.width}×${m.height}', icon: Icons.aspect_ratio),
                    _infoChip(theme, _formatDate(m.createdAt), icon: Icons.access_time),
                  ],
                ),
                // Tag 区域：tagSubdivision 开启时双列（情绪+普通），否则单列可编辑
                if (settings.tagSubdivision) ...[
                  const SizedBox(height: 8),
                  _buildTagEditorSection(theme, l10n, prov, m),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.label, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(l10n.tr('content_tags'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ...m.tags.map((t) => InputChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                        onDeleted: () => prov.removeTag(m.id, t),
                        onPressed: () => _showAddTagDialog(theme, l10n, prov, m, initialTag: t),
                      )),
                      ...m.moods.map((mo) => InputChip(
                        label: Text('${mo['name']} ${_moodWeightStars(mo['weight'] as int)}',
                            style: const TextStyle(fontSize: 11)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        onDeleted: () => prov.removeMood(m.id, mo['name'] as String),
                        onPressed: () => _showEditMoodDialog(theme, l10n, prov, m,
                            mo['name'] as String, mo['weight'] as int),
                      )),
                      // 添加按钮和其他 chip 放一起
                      // 胶囊形（StadiumBorder）+ 极致压缩（VisualDensity -4）使其更扁
                      ActionChip(
                        label: Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
                        onPressed: () => _showAddTagDialog(theme, l10n, prov, m),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                        shape: const StadiumBorder(),
                        tooltip: l10n.tr('add_tag'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // 操作按钮（移动端图片不显示复制）
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (!(isMobile && m.isImageType))
                      _actionButton(theme, l10n.tr('copy'), Icons.copy, _copy),
                    // 系统图集虚拟 Meme 只读：仅支持复制/分享，不显示重命名/收藏/分类/编辑/删除
                    if (!m.isSystemGallery) ...[
                      _actionButton(theme, l10n.tr('rename'), Icons.edit, _rename),
                      _actionButton(theme, l10n.tr('share'), Icons.ios_share, _share),
                      _actionButton(
                        theme,
                        m.isFavorite ? l10n.tr('unfavorite') : l10n.tr('favorite'),
                        m.isFavorite ? Icons.favorite : Icons.favorite_border,
                        () => prov.toggleFavorite(m.id),
                        color: m.isFavorite ? Colors.red : null,
                      ),
                      _actionButton(theme, l10n.tr('select_category'), Icons.label_outline, _showTypeDialog),
                      if (m.isTextLike)
                        _actionButton(theme, l10n.tr('edit'), Icons.edit_note, () => _editText(m)),
                      _actionButton(theme, l10n.tr('delete'), Icons.delete_outline, _confirmDelete, color: Colors.red),
                    ] else ...[
                      _actionButton(theme, l10n.tr('share'), Icons.ios_share, _share),
                    ],
                  ],
                ),
                if (m.type == Meme.typeCharacterCard) ...[
                  const SizedBox(height: 8),
                  // 角色卡预览标题栏：点击切换展开/收起，右侧浮动编辑按钮始终可见
                  _buildCharacterCardHeader(theme, l10n, m),
                  // 内容：收起时隐藏，展开时显示全部字段
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeInOut,
                    crossFadeState: _cardExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity, height: 0),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildCharacterCardPreview(theme, l10n, m),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
          if (_showScrollToTop)
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'scroll_to_top',
                onPressed: () {
                  _lastDetailController?.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                child: const Icon(Icons.arrow_upward, size: 20),
              ),
            ),
        ],
      );
      },
    );
  }

  /// 双列 Tag 编辑区：左列情绪 tag（带权重），右列普通 tag
  Widget _buildTagEditorSection(ThemeData theme, L10n l10n, MemeProvider prov, Meme m) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左列：情绪 tag
        Expanded(
          child: _buildMoodColumn(theme, l10n, prov, m),
        ),
        const SizedBox(width: 8),
        // 右列：普通 tag
        Expanded(
          child: _buildTagColumn(theme, l10n, prov, m),
        ),
      ],
    );
  }

  /// 情绪 tag 列（带权重）
  Widget _buildMoodColumn(ThemeData theme, L10n l10n, MemeProvider prov, Meme m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mood, size: 14, color: theme.colorScheme.tertiary),
            const SizedBox(width: 4),
            Text(l10n.tr('mood_tags'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.tertiary,
              )),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            ...m.moods.map((mo) {
              final name = mo['name'] as String;
              final weight = mo['weight'] as int;
              return InputChip(
                label: Text('$name ${_moodWeightStars(weight)}',
                  style: const TextStyle(fontSize: 10)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                backgroundColor: theme.colorScheme.tertiaryContainer,
                onDeleted: () => prov.removeMood(m.id, name),
                deleteIconColor: theme.colorScheme.tertiary,
                onPressed: () => _showEditMoodDialog(theme, l10n, prov, m, name, weight),
              );
            }),
            ActionChip(
              label: Icon(Icons.add, size: 14, color: theme.colorScheme.tertiary),
              onPressed: () => _showAddMoodDialog(theme, l10n, prov, m),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.12),
              shape: const StadiumBorder(),
              tooltip: l10n.tr('add_mood'),
            ),
          ],
        ),
      ],
    );
  }

  /// 普通 tag 列
  Widget _buildTagColumn(ThemeData theme, L10n l10n, MemeProvider prov, Meme m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.label, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(l10n.tr('content_tags'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              )),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            ...m.tags.map((t) => InputChip(
              label: Text(t, style: const TextStyle(fontSize: 10)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              onDeleted: () => prov.removeTag(m.id, t),
              onPressed: () => _showAddTagDialog(theme, l10n, prov, m, initialTag: t),
            )),
            ActionChip(
              label: Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
              onPressed: () => _showAddTagDialog(theme, l10n, prov, m),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: const StadiumBorder(),
              tooltip: l10n.tr('add_tag'),
            ),
          ],
        ),
      ],
    );
  }

  /// 情绪权重星星（1-5）
  String _moodWeightStars(int weight) {
    return '★' * weight.clamp(1, 5);
  }

  /// 添加情绪对话框（名称 + 权重滑块）
  void _showAddMoodDialog(ThemeData theme, L10n l10n, MemeProvider prov, Meme m) {
    final nameCtrl = TextEditingController();
    int weight = 3;
    // 预设情绪
    final presets = [
      '开心', '大笑', '微笑', '生气', '很生气', '赌气', '悲伤', '哭泣',
      '惊讶', '害怕', '害羞', '得意', '无奈', '困惑', '期待', '无聊',
    ];
    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          title: Text(l10n.tr('add_mood')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 预设情绪选择
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: presets.map((p) => ActionChip(
                  label: Text(p, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    nameCtrl.text = p;
                    setDialogState(() {});
                  },
                )).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('mood_name'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text('${l10n.tr('mood_weight')}: $weight ${_moodWeightStars(weight)}',
                style: const TextStyle(fontSize: 12)),
              Slider(
                value: weight.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: weight.toString(),
                onChanged: (v) => setDialogState(() => weight = v.round()),
              ),
              Text(l10n.tr('mood_weight_hint'),
                style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                prov.addMood(m.id, name, weight);
                Navigator.pop(dCtx);
              },
              child: Text(l10n.tr('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑已有情绪（修改权重或删除）
  void _showEditMoodDialog(ThemeData theme, L10n l10n, MemeProvider prov, Meme m, String name, int currentWeight) {
    int weight = currentWeight;
    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDialogState) => AlertDialog(
          title: Text(name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.tr('mood_weight')}: $weight ${_moodWeightStars(weight)}',
                style: const TextStyle(fontSize: 12)),
              Slider(
                value: weight.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: weight.toString(),
                onChanged: (v) => setDialogState(() => weight = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                prov.removeMood(m.id, name);
                Navigator.pop(dCtx);
              },
              child: Text(l10n.tr('delete'), style: const TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
            FilledButton(
              onPressed: () {
                prov.addMood(m.id, name, weight);
                Navigator.pop(dCtx);
              },
              child: Text(l10n.tr('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  /// 添加/编辑普通 tag 对话框
  void _showAddTagDialog(ThemeData theme, L10n l10n, MemeProvider prov, Meme m, {String? initialTag}) {
    final ctrl = TextEditingController(text: initialTag ?? '');
    final isEdit = initialTag != null;
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(isEdit ? l10n.tr('edit_tag') : l10n.tr('add_tag')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.tr('tag_name'),
            isDense: true,
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () {
                prov.removeTag(m.id, initialTag);
                Navigator.pop(dCtx);
              },
              child: Text(l10n.tr('delete'), style: const TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              if (isEdit) prov.removeTag(m.id, initialTag);
              prov.addTag(m.id, name);
              Navigator.pop(dCtx);
            },
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(ThemeData theme, String text, {IconData? icon, Color? accent}) {
    final iconColor = accent ?? theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: accent ?? theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
    ThemeData theme,
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: c, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type, L10n l10n) {
    // novel 归入文字，pdf 归入文件（分类已下线）
    switch (type) {
      case Meme.typeEmoji:
        return l10n.tr('type_emoji');
      case Meme.typeGif:
        return l10n.tr('type_gif');
      case Meme.typeText:
      case Meme.typeMd:
      case Meme.typeNovel:
        return l10n.tr('type_text');
      case Meme.typeManga:
        return l10n.tr('type_manga');
      case Meme.typeSpriteSheet:
        return l10n.tr('type_sprite_sheet');
      case Meme.typePortrait:
        return l10n.tr('type_portrait');
      case Meme.typeCg:
        return l10n.tr('type_cg');
      case Meme.typeCharacterCard:
        return l10n.tr('type_character_card');
      case Meme.typeVector:
        return l10n.tr('type_vector');
      case Meme.typePsd:
        return l10n.tr('type_psd');
      case Meme.typePdf:
      case Meme.typeFile:
        return l10n.tr('type_file');
      default:
        return l10n.tr('type_image');
    }
  }

  IconData _typeIcon(String type) {
    // novel 归入文字，pdf 归入文件（分类已下线）
    switch (type) {
      case Meme.typeEmoji:
        return Icons.emoji_emotions_outlined;
      case Meme.typeGif:
        return Icons.animation;
      case Meme.typeText:
      case Meme.typeMd:
      case Meme.typeNovel:
        return Icons.text_fields;
      case Meme.typeManga:
        return Icons.menu_book_outlined;
      case Meme.typeSpriteSheet:
        return Icons.view_carousel;
      case Meme.typePortrait:
        return Icons.accessibility_new;
      case Meme.typeCg:
        return Icons.wallpaper_outlined;
      case Meme.typeCharacterCard:
        return Icons.contact_page_outlined;
      case Meme.typeVector:
        return Icons.polyline_outlined;
      case Meme.typePsd:
        return Icons.layers_outlined;
      case Meme.typePdf:
      case Meme.typeFile:
        return Icons.folder_outlined;
      default:
        return Icons.image_outlined;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _copy() {
    final l10n = context.read<LocaleProvider>().l10n;
    final m = _meme;
    // 文字类型：复制文字内容到剪贴板
    if (m.type == Meme.typeText) {
      final text = m.textContent ?? '';
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('no_text_content')), duration: const Duration(seconds: 1)),
        );
        return;
      }
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('copied_text')), duration: const Duration(seconds: 1)),
      );
      return;
    }
    // 表情类型：复制表情符号
    if (m.type == Meme.typeEmoji) {
      final text = m.textContent ?? m.name;
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('copied_to_clipboard')), duration: const Duration(seconds: 1)),
      );
      return;
    }
    // 图片类型：复制文件名（Flutter 无原生图片剪贴板支持）
    Clipboard.setData(ClipboardData(text: m.name));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tr('copied_name', args: {'name': m.name})), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _share() async {
    final m = _meme;
    final storage = context.read<StorageService>();
    if (kIsWeb) {
      // Web：从内存读取字节分享
      final bytes = await storage.readMemeBytes(m.filePath);
      if (bytes == null) return;
      final ext = p.extension(m.filePath).replaceFirst('.', '');
      await Share.shareXFiles([
        XFile.fromData(bytes, name: '${m.name}.$ext', mimeType: 'image/$ext'),
      ]);
    } else {
      // 原生：直接分享文件
      final file = storage.getMemeFile(m.filePath);
      if (file == null || !await file.exists()) return;
      await Share.shareXFiles([XFile(file.path)]);
    }
  }

  void _rename() async {
    final l10n = context.read<LocaleProvider>().l10n;
    final ctrl = TextEditingController(text: _meme.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('rename_title')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: l10n.tr('new_name_hint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      if (mounted) context.read<MemeProvider>().renameMeme(_meme.id, newName);
    }
  }

  /// 编辑文本/小说内容 — 打开编辑弹窗
  void _editText(Meme m) {
    final prov = context.read<MemeProvider>();
    TextEditorDialog.show(
      context,
      type: m.type,
      initialText: m.textContent,
      initialTitle: m.name,
      onSave: (text, title) async {
        await prov.updateMemeText(m.id, text, name: title);
      },
    );
  }

  void _editCharacterCard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CharacterCardEditorScreen(meme: _meme),
      ),
    );
  }

  /// 角色卡数据预览（只读展示已有数据，未读取到时提示）
  List<Widget> _buildCharacterCardPreview(ThemeData theme, L10n l10n, Meme m) {
    final data = m.characterData;
    if (data == null || data.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            l10n.tr('no_text_content'),
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
          ),
        ),
      ];
    }

    String fieldStr(String key) {
      final v = data[key];
      if (v == null) return '';
      if (v is String) return v;
      return v.toString();
    }

    final name = fieldStr('name');
    final description = fieldStr('description');
    final personality = fieldStr('personality');
    final scenario = fieldStr('scenario');
    final firstMes = fieldStr('first_mes');
    final mesExample = fieldStr('mes_example');
    final systemPrompt = fieldStr('system_prompt');
    final postHistory = fieldStr('post_history_instructions');
    final notes = fieldStr('notes');
    final creator = fieldStr('creator');
    final characterVersion = fieldStr('character_version');
    final version = fieldStr('version');
    final spec = fieldStr('spec');
    final specVersion = fieldStr('spec_version');
    final altGreetings = data['alternate_greetings'];
    final tags = data['tags'];

    Widget row(String label, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 4),
            // 使用 MarkdownBody 渲染字段内容，支持 **粗体** / *斜体* / 列表 / 引用 / 代码块等
            MarkdownBody(
              data: value,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodySmall,
                h1: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                h2: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                h3: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                code: TextStyle(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                codeblockDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 2)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    if (name.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ));
    }
    // 元信息行：作者 / 角色卡版本 / 规范
    final metaParts = <String>[
      if (creator.isNotEmpty) '${l10n.tr('char_creator')}: $creator',
      if (characterVersion.isNotEmpty) '${l10n.tr('char_character_version')}: $characterVersion',
      if (version.isNotEmpty) '${l10n.tr('char_version')}: $version',
      if (spec.isNotEmpty) '${l10n.tr('char_spec')}: $spec',
      if (specVersion.isNotEmpty) '${l10n.tr('char_spec_version')}: $specVersion',
    ];
    if (metaParts.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: metaParts.map((s) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(s, style: theme.textTheme.labelSmall),
          )).toList(),
        ),
      ));
    }
    // 标签
    if (tags is List && tags.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: tags.map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('#$t', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
          )).toList(),
        ),
      ));
    }
    children.addAll([
      row(l10n.tr('char_description'), description),
      row(l10n.tr('char_personality'), personality),
      row(l10n.tr('char_scenario'), scenario),
      row(l10n.tr('char_first_mes'), firstMes),
      row(l10n.tr('char_mes_example'), mesExample),
      row(l10n.tr('char_system_prompt'), systemPrompt),
      row(l10n.tr('char_post_history_instructions'), postHistory),
      row(l10n.tr('char_notes'), notes),
    ]);
    // 备选开场白
    if (altGreetings is List && altGreetings.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('char_alt_greetings'), style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 4),
            ...altGreetings.asMap().entries.map((e) {
              final v = e.value;
              final s = v is String ? v : v.toString();
              if (s.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: MarkdownBody(
                  data: '[${e.key + 1}] $s',
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodySmall,
                  ),
                ),
              );
            }),
          ],
        ),
      ));
    }
    // 角色书（仅展示是否存在 + 条目数）
    final book = data['character_book'];
    if (book is Map) {
      final entries = book['entries'];
      final count = entries is List ? entries.length : 0;
      children.add(row(l10n.tr('char_character_book'), '${l10n.tr('char_extensions')}: $count'));
    }
    // 扩展字段（仅展示 key 列表）
    final ext = data['extensions'];
    if (ext is Map && ext.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('char_extensions'), style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: ext.keys.map((k) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(k.toString(), style: theme.textTheme.labelSmall),
              )).toList(),
            ),
          ],
        ),
      ));
    }

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ];
  }

  /// 角色卡预览标题栏：点击切换展开/收起，右侧始终显示编辑按钮
  /// 默认收起，避免长内容撑爆详情面板；展开后显示全部字段
  Widget _buildCharacterCardHeader(ThemeData theme, L10n l10n, Meme m) {
    final name = (m.characterData?['name'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.contact_page_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name.isNotEmpty ? name : l10n.tr('type_character_card'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 编辑按钮：始终可见，无需展开即可点
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: l10n.tr('edit_character_card'),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _editCharacterCard,
          ),
          // 展开/收起切换按钮
          IconButton(
            icon: Icon(
              _cardExpanded ? Icons.expand_less : Icons.expand_more,
              size: 22,
            ),
            tooltip: _cardExpanded ? l10n.tr('collapse') : l10n.tr('expand'),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() {
              _cardExpanded = !_cardExpanded;
              _onDetailScroll();
            }),
          ),
        ],
      ),
    );
  }

  void _showTypeDialog() {
    final l10n = context.read<LocaleProvider>().l10n;
    final settings = context.read<SettingsProvider>();
    final allTypes = [
      {'type': Meme.typeEmoji, 'label': l10n.tr('type_emoji'), 'icon': Icons.emoji_emotions_outlined},
      {'type': Meme.typeGif, 'label': l10n.tr('type_gif'), 'icon': Icons.animation},
      {'type': Meme.typeImage, 'label': l10n.tr('type_image'), 'icon': Icons.image_outlined},
      {'type': Meme.typeText, 'label': l10n.tr('type_text'), 'icon': Icons.text_fields},
      {'type': Meme.typePortrait, 'label': l10n.tr('type_portrait'), 'icon': Icons.accessibility_new},
      {'type': Meme.typeCg, 'label': l10n.tr('type_cg'), 'icon': Icons.wallpaper_outlined},
      {'type': Meme.typeCharacterCard, 'label': l10n.tr('type_character_card'), 'icon': Icons.contact_page_outlined},
      {'type': Meme.typeVector, 'label': l10n.tr('type_vector'), 'icon': Icons.polyline_outlined},
      {'type': Meme.typePsd, 'label': l10n.tr('type_psd'), 'icon': Icons.layers_outlined},
      {'type': Meme.typeManga, 'label': l10n.tr('type_manga'), 'icon': Icons.menu_book_outlined},
      {'type': Meme.typeSpriteSheet, 'label': l10n.tr('type_sprite_sheet'), 'icon': Icons.view_carousel},
      {'type': Meme.typeFile, 'label': l10n.tr('type_file'), 'icon': Icons.folder_outlined},
    ];
    // 仅显示已启用的分类 + 当前 meme 所属分类（即便被隐藏也可保持）
    // 同分类下的旧类型也视为已启用（pdf→file, novel→text）
    final types = allTypes.where((t) {
      final type = t['type'] as String;
      if (settings.isCategoryVisible(type)) return true;
      if (_meme.type == type) return true;
      if (type == Meme.typeFile && _meme.type == Meme.typePdf) return true;
      if (type == Meme.typeText &&
          (_meme.type == Meme.typeMd || _meme.type == Meme.typeNovel)) return true;
      return false;
    }).toList();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('select_category')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: types.map((t) {
            final type = t['type'] as String;
            final label = t['label'] as String;
            final icon = t['icon'] as IconData;
            // 同分类下的旧类型也视为选中（pdf→file, novel/md→text）
            final selected = _meme.type == type ||
                (type == Meme.typeFile && _meme.type == Meme.typePdf) ||
                (type == Meme.typeText &&
                    (_meme.type == Meme.typeMd ||
                     _meme.type == Meme.typeNovel));
            return ListTile(
              leading: Icon(icon, color: selected ? Theme.of(dCtx).colorScheme.primary : null),
              title: Text(label),
              trailing: selected ? Icon(Icons.check, color: Theme.of(dCtx).colorScheme.primary) : null,
              onTap: () async {
                if (mounted) {
                  context.read<MemeProvider>().setMemeType(_meme.id, type);
                }
                Navigator.pop(dCtx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(l10n.tr('cancel'))),
        ],
      ),
    );
  }

  void _confirmDelete() async {
    final l10n = context.read<LocaleProvider>().l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('delete_meme_title')),
        content: Text(l10n.tr('delete_confirm', args: {'name': _meme.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(l10n.tr('delete'))),
        ],
      ),
    );
    if (confirm == true) {
      if (mounted) {
        final prov = context.read<MemeProvider>();
        await prov.deleteMeme(_meme.id);
        if (mounted) Navigator.pop(context);
      }
    }
  }
}

/// 序列帧绘制器：从原图裁剪指定帧区域
class _FramePainter extends CustomPainter {
  final ui.Image image;
  final int frameIndex;
  final int cols;
  final int rows;

  _FramePainter({
    required this.image,
    required this.frameIndex,
    required this.cols,
    required this.rows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = image.width / cols;
    final frameH = image.height / rows;
    final col = frameIndex % cols;
    final row = frameIndex ~/ cols;
    final src = Rect.fromLTWH(col * frameW, row * frameH, frameW, frameH);
    final dst = Offset.zero & size;
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frameIndex != frameIndex || old.image != image;
}
