import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../providers/settings_provider.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';
import '../models/meme.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import 'keyboard_setup_screen.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _sectionHeader(l10n.tr('appearance'), cs),
          _languageTile(context, l10n),
          const Divider(indent: 16, endIndent: 16),
          _themeModeTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          _gridColumnsTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          if (_isDesktopOrWeb()) ...[
            _landscapePreviewTile(settings, l10n),
            const Divider(indent: 16, endIndent: 16),
          ],
          if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ...[
            _mobileLongPressTile(settings, l10n),
            const Divider(indent: 16, endIndent: 16),
          ],
          _tagSubdivisionTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _monetTile(settings, l10n),
            if (!settings.useMonet) ...[
              const SizedBox(height: 8),
              _presetPicker(settings, cs, l10n),
            ],
          ] else ...[
            const SizedBox(height: 8),
            _presetPicker(settings, cs, l10n),
          ],
          const SizedBox(height: 16),

          _sectionHeader(l10n.tr('background'), cs),
          _backgroundTile(settings, l10n),
          if (settings.hasCustomBg) ...[
            const Divider(indent: 16, endIndent: 16),
            _bgBlurTile(settings, l10n),
            const Divider(indent: 16, endIndent: 16),
            _bgOpacityTile(settings, l10n),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l10n.tr('clear_background'), style: const TextStyle(color: Colors.red)),
              onTap: () => settings.setBgImagePath(null),
            ),
          ],
          const SizedBox(height: 16),

          _sectionHeader(l10n.tr('data'), cs),
          if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows) ...[
            _storageLocationTile(settings, l10n),
            const Divider(indent: 16, endIndent: 16),
          ],
          _autoClassifyTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          _cardDisplayTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          _categoryManageTile(settings, l10n),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(l10n.tr('import_data')),
            subtitle: Text(l10n.tr('import_data_desc')),
            onTap: () => _importZip(context, l10n),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(l10n.tr('export_data')),
            subtitle: Text(l10n.tr('export_data_desc')),
            onTap: () => _showExportOptions(context, l10n),
          ),
          const SizedBox(height: 16),

          _sectionHeader(l10n.tr('cloud_sync'), cs),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: Text(l10n.tr('enable_webdav')),
            subtitle: Text(l10n.tr('webdav_desc')),
            value: settings.useWebDav,
            onChanged: (v) => settings.setUseWebDav(v),
          ),
          if (settings.useWebDav) ...[
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(l10n.tr('webdav_config_title')),
              subtitle: Text(settings.webDavBaseUrl != null ? l10n.tr('webdav_configured') : l10n.tr('webdav_not_configured')),
              onTap: () => _showWebDavConfigDialog(context, l10n),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(l10n.tr('sync_all_data')),
              subtitle: Text(l10n.tr('sync_all_desc')),
              onTap: () => _syncAllToWebDav(context, l10n),
            ),
          ],
          const SizedBox(height: 16),

          _sectionHeader(l10n.tr('keyboard_setup'), cs),
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: Text(l10n.tr('keyboard_setup')),
            subtitle: Text(l10n.tr('keyboard_setup_desc')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeyboardSetupScreen()),
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          _emojiEffectTile(settings, l10n),

          const SizedBox(height: 16),
          _sectionHeader(l10n.tr('about'), cs),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.tr('version')),
            subtitle: Text(_version.isEmpty ? '0.0.1-dev+$_buildNumber' : '$_version+$_buildNumber'),
            trailing: const Icon(Icons.history, size: 20),
            onTap: () => _showChangelog(context, l10n),
          ),
          ListTile(
            leading: Icon(_checking ? Icons.hourglass_top : Icons.system_update_outlined),
            title: Text(l10n.tr('check_update')),
            subtitle: Text(l10n.tr('check_update_desc')),
            onTap: _checking ? null : () => _checkUpdate(context, l10n),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('GitHub'),
            subtitle: const Text('NetheritePickaxe/mako_meme'),
            onTap: () => UpdateService.openUrl('https://github.com/NetheritePickaxe/mako_meme'),
          ),
        ],
      ),
    );
  }

  Widget _storageLocationTile(SettingsProvider settings, L10n l10n) {
    final isCustom = settings.storageLocation == 'custom' && settings.customStoragePath != null;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(l10n.tr('storage_location')),
          subtitle: Text(
            isCustom
                ? settings.customStoragePath!
                : l10n.tr('app_data'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'app', icon: const Icon(Icons.storage, size: 18)),
              ButtonSegment(value: 'custom', icon: const Icon(Icons.folder_open, size: 18)),
            ],
            selected: {settings.storageLocation},
            onSelectionChanged: (v) async {
              final isMobile = !kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS);
              if (v.first == 'custom') {
                final path = await FilePicker.platform.getDirectoryPath(
                  dialogTitle: l10n.tr('custom_folder'),
                );
                if (path != null) {
                  if (isMobile) {
                    await _ensureNomedia(path);
                  }
                  await settings.setCustomStoragePath(path);
                  await settings.setStorageLocation('custom');
                  if (mounted) {
                    _showRestartDialog(l10n);
                  }
                }
              } else {
                if (isMobile && settings.customStoragePath != null) {
                  await _removeNomedia(settings.customStoragePath!);
                }
                await settings.setStorageLocation('app');
                if (mounted) {
                  _showRestartDialog(l10n);
                }
              }
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        if (isCustom) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tr('data_stored_at', args: {'path': settings.customStoragePath ?? ''}),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showRestartDialog(L10n l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('restart_needed')),
        content: Text(l10n.tr('restart_msg')),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    );
  }

  /// 在自定义路径根目录生成 .nomedia，避免相册扫描表情包
  Future<void> _ensureNomedia(String rootPath) async {
    try {
      final file = File(p.join(rootPath, '.nomedia'));
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
    } catch (_) {}
  }

  /// 切回应用存储时移除 .nomedia
  Future<void> _removeNomedia(String rootPath) async {
    try {
      final file = File(p.join(rootPath, '.nomedia'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Widget _sectionHeader(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
    );
  }

  Widget _languageTile(BuildContext context, L10n l10n) {
    final localeProv = context.watch<LocaleProvider>();
    // 使用完整 locale code（带国家码）作为下拉值，确保与 supportedLocales 匹配
    final currentValue = localeProv.locale.countryCode != null
        ? '${localeProv.locale.languageCode}_${localeProv.locale.countryCode}'.toLowerCase()
        : localeProv.locale.languageCode.toLowerCase();
    // 当前语言排第一，另一种语言排第二
    final allLangs = const [
      ('zh_cn', '简体中文'),
      ('en_us', 'English'),
    ];
    final sorted = [...allLangs]..sort((a, b) {
        if (a.$1 == currentValue) return -1;
        if (b.$1 == currentValue) return 1;
        return 0;
      });
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.language),
      title: Text(l10n.tr('language')),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButton<String>(
          value: currentValue,
          underline: const SizedBox(),
          isDense: true,
          style: Theme.of(context).textTheme.bodyLarge,
          borderRadius: BorderRadius.circular(16),
          items: sorted
              .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            final parts = val.split('_');
            final locale = parts.length == 2
                ? Locale(parts[0], parts[1])
                : Locale(parts[0]);
            localeProv.setLocale(locale);
          },
        ),
      ),
    );
  }

  Widget _themeModeTile(SettingsProvider settings, L10n l10n) {
    final showPureBlack = settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: Text(l10n.tr('theme_mode')),
          trailing: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(l10n.tr('system'))),
              ButtonSegment(value: ThemeMode.light, label: Text(l10n.tr('light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.tr('dark'))),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (v) => settings.setThemeMode(v.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        if (showPureBlack)
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: Text(l10n.tr('pure_black')),
            subtitle: Text(l10n.tr('pure_black_desc')),
            value: settings.pureBlack,
            onChanged: (v) => settings.setPureBlack(v),
          ),
      ],
    );
  }

  Widget _gridColumnsTile(SettingsProvider settings, L10n l10n) {
    final options = [0, 2, 3, 4, 5, 6, 7, 8];
    return ListTile(
      leading: const Icon(Icons.grid_view_outlined),
      title: Text(l10n.tr('grid_columns')),
      subtitle: Text(settings.gridColumns == 0
          ? l10n.tr('auto_col')
          : l10n.tr('n_columns', args: {'count': settings.gridColumns.toString()})),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButton<int>(
          value: settings.gridColumns,
          underline: const SizedBox(),
          isDense: true,
          borderRadius: BorderRadius.circular(16),
          items: List.generate(options.length, (i) {
            final v = options[i];
            return DropdownMenuItem(
              value: v,
              child: Text(v == 0 ? l10n.tr('auto_col') : '$v'),
            );
          }),
          onChanged: (v) { if (v != null) settings.setGridColumns(v); },
        ),
      ),
    );
  }

  /// 是否为桌面端或 Web（用于决定是否显示横屏预览选项）
  bool _isDesktopOrWeb() {
    if (kIsWeb) return true;
    final p = defaultTargetPlatform;
    return p == TargetPlatform.windows || p == TargetPlatform.macOS || p == TargetPlatform.linux;
  }

  Widget _landscapePreviewTile(SettingsProvider settings, L10n l10n) {
    return SwitchListTile(
      secondary: const Icon(Icons.view_sidebar_outlined),
      title: Text(l10n.tr('landscape_preview')),
      subtitle: Text(l10n.tr('landscape_preview_desc')),
      value: settings.landscapePreview,
      onChanged: (v) => settings.setLandscapePreview(v),
    );
  }

  Widget _mobileLongPressTile(SettingsProvider settings, L10n l10n) {
    return ListTile(
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(l10n.tr('long_press_action')),
      subtitle: Text(settings.mobileLongPressIsMenu
          ? l10n.tr('long_press_menu')
          : l10n.tr('long_press_share')),
      trailing: SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'share',
            icon: const Icon(Icons.share, size: 18),
          ),
          ButtonSegment(
            value: 'menu',
            icon: const Icon(Icons.menu, size: 18),
          ),
        ],
        selected: {settings.mobileLongPress},
        onSelectionChanged: (s) => settings.setMobileLongPress(s.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _tagSubdivisionTile(SettingsProvider settings, L10n l10n) {
    return SwitchListTile(
      secondary: const Icon(Icons.label_outline),
      title: Text(l10n.tr('tag_subdivision')),
      subtitle: Text(l10n.tr('tag_subdivision_desc')),
      value: settings.tagSubdivision,
      onChanged: (v) => settings.setTagSubdivision(v),
    );
  }

  Widget _backgroundTile(SettingsProvider settings, L10n l10n) {
    final hasBg = settings.hasCustomBg;
    return ListTile(
      leading: const Icon(Icons.wallpaper_outlined),
      title: Text(l10n.tr('custom_background')),
      subtitle: Text(hasBg ? l10n.tr('background_set_desc') : l10n.tr('background_empty_desc')),
      trailing: hasBg
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : null,
    );
  }

  Widget _bgBlurTile(SettingsProvider settings, L10n l10n) {
    return ListTile(
      leading: const Icon(Icons.blur_on),
      title: Text(l10n.tr('background_blur')),
      subtitle: Slider(
        value: settings.bgBlur,
        min: 0,
        max: 30,
        divisions: 30,
        label: settings.bgBlur.toStringAsFixed(0),
        onChanged: (v) => settings.setBgBlur(v),
      ),
      trailing: Text(settings.bgBlur.toStringAsFixed(0)),
    );
  }

  Widget _bgOpacityTile(SettingsProvider settings, L10n l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ListTile(
      leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      title: Text(l10n.tr('background_dimming')),
      subtitle: Slider(
        value: settings.bgOpacity,
        min: 0,
        max: 0.9,
        divisions: 18,
        label: '${(settings.bgOpacity * 100).round()}%',
        onChanged: (v) => settings.setBgOpacity(v),
      ),
      trailing: Text('${(settings.bgOpacity * 100).round()}%'),
    );
  }

  Widget _autoClassifyTile(SettingsProvider settings, L10n l10n) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: Text(l10n.tr('auto_classify')),
          subtitle: Text(l10n.tr('auto_classify_desc')),
          value: settings.autoClassify,
          onChanged: (v) => settings.setAutoClassify(v),
        ),
        if (settings.autoClassify) ...[
          ListTile(
            leading: const Icon(Icons.straighten_outlined),
            title: Text(l10n.tr('classify_threshold')),
            subtitle: Text(l10n.tr('square_threshold', args: {'ratio': settings.classifyRatio.toStringAsFixed(1)})),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: settings.classifyRatio,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                label: settings.classifyRatio.toStringAsFixed(1),
                onChanged: (v) => settings.setClassifyRatio(v),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.tr('reclassify_all')),
            subtitle: Text(l10n.tr('reclassify_desc')),
            onTap: () => _reclassifyAll(context, settings, l10n),
          ),
        ],
      ],
    );
  }

  Widget _categoryManageTile(SettingsProvider settings, L10n l10n) {
    // 所有内置分类
    final builtinCats = <String>[
      Meme.typeEmoji, Meme.typeGif, Meme.typeImage, Meme.typeText,
      Meme.typePortrait, Meme.typeCg, Meme.typeCharacterCard,
      Meme.typeVector, Meme.typePsd, Meme.typePdf, Meme.typeNovel,
    ];
    final visibleCount = builtinCats.where(settings.isCategoryVisible).length;
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: const Icon(Icons.category_outlined),
      title: Text(l10n.tr('category_manage')),
      subtitle: Text('$visibleCount / ${builtinCats.length}'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        // 内置分类 — 圆角卡片容器内放 FilterChip
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: builtinCats.map((type) {
              final m = Meme(id: '', name: '', createdAt: DateTime.now(), type: type, filePath: '');
              final label = l10n.tr(m.typeLabelKey);
              final visible = settings.isCategoryVisible(type);
              return FilterChip(
                label: Text(label),
                selected: visible,
                onSelected: (v) => settings.toggleCategoryVisibility(type),
                shape: const StadiumBorder(),
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // 自定义分类标题 + 添加按钮
        Row(
          children: [
            Text(l10n.tr('custom_categories'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: l10n.tr('add_category'),
              onPressed: () => _showAddCustomCategoryDialog(settings, l10n),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (settings.customCategories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.tr('no_custom_categories'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: settings.customCategories.map((name) {
                return Chip(
                  label: Text(name),
                  onDeleted: () => settings.removeCustomCategory(name),
                  deleteIconColor: cs.onSurfaceVariant,
                  shape: const StadiumBorder(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  void _showAddCustomCategoryDialog(SettingsProvider settings, L10n l10n) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('add_category')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.tr('category_name_hint'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                settings.addCustomCategory(ctrl.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.tr('create')),
          ),
        ],
      ),
    );
  }

  Widget _cardDisplayTile(SettingsProvider settings, L10n l10n) {
    final cs = Theme.of(context).colorScheme;
    final enabledCount = [
      settings.showCardName,
      settings.showCardTags,
      settings.showCardType,
      settings.showCardExt,
    ].where((v) => v).length;
    return ExpansionTile(
      leading: const Icon(Icons.view_carousel_outlined),
      title: Text(l10n.tr('card_display')),
      subtitle: Text('$enabledCount / 4'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.label_outline),
                  title: Text(l10n.tr('card_show_name')),
                  value: settings.showCardName,
                  onChanged: (v) => settings.setShowCardName(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.tag),
                  title: Text(l10n.tr('card_show_tags')),
                  value: settings.showCardTags,
                  onChanged: (v) => settings.setShowCardTags(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.category_outlined),
                  title: Text(l10n.tr('card_show_type')),
                  value: settings.showCardType,
                  onChanged: (v) => settings.setShowCardType(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.extension),
                  title: Text(l10n.tr('card_show_ext')),
                  value: settings.showCardExt,
                  onChanged: (v) => settings.setShowCardExt(v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emojiEffectTile(SettingsProvider settings, L10n l10n) {
    final cs = Theme.of(context).colorScheme;
    final options = [
      ('rain', l10n.tr('effect_rain'), Icons.cloudy_snowing),
      ('explosion', l10n.tr('effect_explosion'), Icons.burst_mode),
      ('both', l10n.tr('effect_both'), Icons.swap_vert),
    ];
    final currentLabel = options.firstWhere((o) => o.$1 == settings.emojiEffectType,
        orElse: () => options.first).$2;
    return ListTile(
      leading: const Icon(Icons.celebration_outlined),
      title: Text(l10n.tr('emoji_effect')),
      subtitle: Text('$currentLabel · ${l10n.tr('emoji_effect_desc')}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButton<String>(
          value: settings.emojiEffectType,
          underline: const SizedBox(),
          isDense: true,
          style: Theme.of(context).textTheme.bodyLarge,
          borderRadius: BorderRadius.circular(16),
          items: options
              .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
              .toList(),
          onChanged: (val) {
            if (val != null) settings.setEmojiEffectType(val);
          },
        ),
      ),
    );
  }

  Future<void> _reclassifyAll(BuildContext context, SettingsProvider settings, L10n l10n) async {
    final prov = context.read<MemeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('reclassify_title')),
        content: Text(l10n.tr('reclassify_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('continue'))),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(l10n.tr('reclassifying'))),
            ],
          ),
        ),
      ),
    );

    final result = await prov.reclassifyAllByAspectRatio(settings.classifyRatio);

    if (context.mounted) {
      Navigator.of(context).pop(); // 关闭进度对话框
      final e = result['emoji'] ?? 0;
      final i = result['image'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('reclassify_done', args: {'emoji': e.toString(), 'image': i.toString()})),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _monetTile(SettingsProvider settings, L10n l10n) {
    return SwitchListTile(
      secondary: const Icon(Icons.palette_outlined),
      title: Text(l10n.tr('monet_title')),
      subtitle: Text(l10n.tr('monet_desc')),
      value: settings.useMonet,
      onChanged: (v) => settings.setUseMonet(v),
    );
  }

  Widget _presetPicker(SettingsProvider settings, ColorScheme cs, L10n l10n) {
    final presets = AppTheme.presets;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('color_scheme'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
          ),
          const SizedBox(height: 8),
          ...presets.asMap().entries.map((entry) {
            final idx = entry.key;
            final preset = entry.value;
            final selected = idx == settings.presetIndex;
            return _presetCard(preset, selected, cs, () => settings.setPreset(idx));
          }),
          const SizedBox(height: 4),
          _customPresetCard(settings, cs, l10n),
        ],
      ),
    );
  }

  Widget _presetCard(ColorSchemePreset preset, bool selected, ColorScheme cs, VoidCallback onTap) {
    // 派生 M3 色板，预览 primary / primaryContainer / secondary / tertiary 四色块
    final previewScheme = ColorScheme.fromSeed(seedColor: preset.seed, brightness: cs.brightness);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: cs.primary, width: 2)
              : Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          color: selected ? cs.primaryContainer.withValues(alpha: 0.12) : null,
        ),
        child: Row(
          children: [
            // 色卡：四个圆角方形色块横向排列，直观展示配色方案
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _swatch(previewScheme.primary),
                const SizedBox(width: 4),
                _swatch(previewScheme.primaryContainer),
                const SizedBox(width: 4),
                _swatch(previewScheme.secondary),
                const SizedBox(width: 4),
                _swatch(previewScheme.tertiary),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                preset.name,
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }

  /// 圆角方形色卡
  Widget _swatch(Color color, [double size = 30]) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * 0.23),
      border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.5),
    ),
  );

  Widget _customPresetCard(SettingsProvider settings, ColorScheme cs, L10n l10n) {
    final selected = settings.presetIndex >= AppTheme.presets.length;
    final previewScheme = ColorScheme.fromSeed(seedColor: settings.customSeed, brightness: cs.brightness);
    return InkWell(
      onTap: () => _showCustomColorPicker(context, settings, cs, l10n),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: cs.primary, width: 2)
              : Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          color: selected ? cs.primaryContainer.withValues(alpha: 0.12) : null,
        ),
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _swatch(previewScheme.primary),
                const SizedBox(width: 4),
                _swatch(previewScheme.primaryContainer),
                const SizedBox(width: 4),
                _swatch(previewScheme.secondary),
                const SizedBox(width: 4),
                _swatch(previewScheme.tertiary),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selected ? l10n.tr('custom_saved') : l10n.tr('custom_color_scheme'),
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
            Icon(Icons.edit, size: 18, color: cs.primary),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: cs.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  void _showCustomColorPicker(BuildContext context, SettingsProvider settings, ColorScheme cs, L10n l10n) {
    final hexCtrl = TextEditingController(
      text: settings.customSeed.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2),
    );

    Color currentColor = settings.customSeed;

    void setColor(Color c) {
      currentColor = c;
      hexCtrl.text = c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bCtx).viewInsets.bottom,
            left: 16, right: 16, top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.tr('custom_color_scheme'),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // 色轮 + 预览
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: _ColorWheel(
                      initialColor: currentColor,
                      onColorChanged: (c) {
                        setModalState(() => setColor(c));
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 当前颜色预览块
                  Column(
                    children: [
                      Text(l10n.tr('preview'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: currentColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 派生色板预览（圆角方形）
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _swatch(ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.light).primary, 18),
                              const SizedBox(width: 3),
                              _swatch(ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.light).secondary, 18),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _swatch(ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.dark).primary, 18),
                              const SizedBox(width: 3),
                              _swatch(ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.dark).secondary, 18),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(l10n.tr('lightness'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: HSLColor.fromColor(currentColor).lightness,
                      onChanged: (v) {
                        final hsl = HSLColor.fromColor(currentColor);
                        setModalState(() => setColor(hsl.withLightness(v).toColor()));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // HEX 输入 — 不使用 maxLength 以避免显示计数器
              Row(
                children: [
                  Text('#', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: hexCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        hintText: 'RRGGBB',
                        counterText: '',
                      ),
                      maxLength: 6,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (v) {
                        final hex = v.replaceAll('#', '');
                        if (hex.length == 6) {
                          final parsed = int.tryParse('FF$hex', radix: 16);
                          if (parsed != null) {
                            setModalState(() => setColor(Color(parsed)));
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(bCtx),
                      child: Text(l10n.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        settings.setCustomSeed(currentColor);
                        Navigator.pop(bCtx);
                      },
                      child: Text(l10n.tr('save')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportOptions(BuildContext context, L10n l10n) {
    final canSaveToGallery = !kIsWeb;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(l10n.tr('export_zip')),
              subtitle: Text(l10n.tr('export_zip_desc')),
              onTap: () {
                Navigator.pop(ctx);
                _exportData(context, l10n);
              },
            ),
            if (canSaveToGallery)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l10n.tr('save_to_gallery')),
                subtitle: Text(l10n.tr('save_to_gallery_desc')),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveToGallery(context, l10n);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToGallery(BuildContext context, L10n l10n) async {
    final storage = context.read<StorageService>();
    final memes = storage.getAllMemes();
    if (memes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('no_exportable'))),
        );
      }
      return;
    }

    // 确定目标目录
    Directory? targetDir;
    try {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // 桌面：保存到用户主目录下的 Pictures
        final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
        String picturesPath;
        if (defaultTargetPlatform == TargetPlatform.windows) {
          picturesPath = p.join(home ?? 'C:\\Users', 'Pictures', 'Mako Meme');
        } else if (defaultTargetPlatform == TargetPlatform.macOS) {
          picturesPath = p.join(home ?? '/Users', 'Pictures', 'Mako Meme');
        } else {
          // Linux
          picturesPath = p.join(home ?? '/home', 'Pictures', 'Mako Meme');
        }
        targetDir = Directory(picturesPath);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // Android：优先尝试公共 Pictures 目录（会被相册扫描）
        final publicDir = Directory('/storage/emulated/0/Pictures/Mako Meme');
        try {
          if (!await publicDir.exists()) await publicDir.create(recursive: true);
          // 测试写入权限
          final testFile = File(p.join(publicDir.path, '.mako_test'));
          await testFile.writeAsString('test');
          await testFile.delete();
          targetDir = publicDir;
        } catch (_) {
          // 回退到应用专属外部存储（不会被相册自动扫描）
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            targetDir = Directory(p.join(ext.path, 'Pictures', 'Mako Meme'));
          }
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS：保存到文档目录
        final docs = await getApplicationDocumentsDirectory();
        targetDir = Directory(p.join(docs.path, 'Mako Meme'));
      }
    } catch (_) {}

    if (targetDir == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('cannot_determine_dir'))),
        );
      }
      return;
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    if (!context.mounted) return;

    final total = memes.length;
    final progressNotifier = ValueNotifier<int>(0);

    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progressNotifier,
            builder: (_, done, __) => Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(l10n.tr('saving_progress', args: {'done': done.toString(), 'total': total.toString()}))),
              ],
            ),
          ),
        ),
      ),
    );

    int done = 0;
    int failed = 0;
    for (final meme in memes) {
      try {
        final abs = storage.getMemeAbsolutePath(meme.filePath);
        if (abs == null) { failed++; continue; }
        final srcFile = File(abs);
        if (!await srcFile.exists()) { failed++; continue; }
        // 用唯一文件名避免覆盖
        final ext = p.extension(meme.filePath);
        final destName = '${meme.name}$ext';
        final destFile = File(p.join(targetDir.path, destName));
        // 若重名，加序号
        var finalPath = destFile.path;
        var counter = 1;
        while (await File(finalPath).exists()) {
          finalPath = p.join(targetDir.path, '${meme.name} ($counter)$ext');
          counter++;
        }
        await srcFile.copy(finalPath);
        done++;
      } catch (_) {
        failed++;
      }
      progressNotifier.value = done + failed;
    }

    progressNotifier.dispose();
    if (context.mounted) {
      Navigator.of(context).pop(); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('saved_n_to', args: {'done': done.toString(), 'path': targetDir.path}) + (failed > 0 ? ' ($failed)' : '')),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _exportData(BuildContext context, L10n l10n) async {
    final storage = context.read<StorageService>();

    // Web 端：用内存字节生成 zip 并触发下载
    if (kIsWeb) {
      final bytes = await storage.exportDataBytes();
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.tr('export_failed_msg'))),
          );
        }
        return;
      }
      // Web 端 saveFile 接收 bytes 直接下载
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: l10n.tr('save_backup'),
        fileName: 'mako_meme_backup.zip',
        bytes: bytes,
      );
      if (saved == null) {
        // 用户取消或下载失败
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('export_success_msg'))),
        );
      }
      return;
    }

    // 原生端：生成临时文件，让用户选择保存位置
    final path = await storage.exportData();
    if (path == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('export_failed_msg'))),
        );
      }
      return;
    }

    final file = File(path);
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: l10n.tr('save_backup'),
      fileName: 'mako_meme_backup.zip',
      type: FileType.any,
    );
    if (saved != null) {
      await file.copy(saved);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('export_success_msg'))),
        );
      }
    }
    await file.delete();
  }

  Future<void> _importZip(BuildContext ctx, L10n l10n) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!ctx.mounted) return;

    final zipFile = result.files.first;
    if (zipFile.path == null) return;

    final storage = ctx.read<StorageService>();
    final prov = ctx.read<MemeProvider>();

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(l10n.tr('import_data_title')),
        content: Text(l10n.tr('import_confirm_msg', args: {'filename': zipFile.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.tr('import'))),
        ],
      ),
    );
    if (!ctx.mounted) return;
    if (confirmed != true) return;

    final count = await storage.importZip(zipFile.path!);
    await prov.loadAll();

    if (ctx.mounted) {
      String msg;
      if (count == 0) {
        msg = l10n.tr('import_success_msg');
      } else if (count > 0) {
        msg = l10n.tr('imported_n_images', args: {'count': count.toString()});
      } else {
        msg = l10n.tr('import_failed_msg');
      }
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _checkUpdate(BuildContext ctx, L10n l10n) async {
    setState(() => _checking = true);
    final service = UpdateService();
    final info = await service.check();
    if (!ctx.mounted) return;
    setState(() => _checking = false);

    if (info == null) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l10n.tr('already_latest'))),
      );
      return;
    }

    if (!ctx.mounted) return;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('new_version_available')),
        content: Text(l10n.tr('version_available', args: {'version': info.version})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('later'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('download'))),
        ],
      ),
    );
    if (result == true) {
      await UpdateService.openUrl(info.downloadUrl);
    }
  }

  void _showWebDavConfigDialog(BuildContext context, L10n l10n) {
    final settings = context.read<SettingsProvider>();
    final baseUrlCtrl = TextEditingController(text: settings.webDavBaseUrl ?? '');
    final usernameCtrl = TextEditingController(text: settings.webDavUsername ?? '');
    final passwordCtrl = TextEditingController(text: settings.webDavPassword ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('webdav_config_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrlCtrl,
                decoration: InputDecoration(
                  labelText: l10n.tr('server_url_label'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.tr('username_label'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('password_label'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final webDavService = WebDavService(
                baseUrl: baseUrlCtrl.text,
                username: usernameCtrl.text,
                password: passwordCtrl.text,
              );

              final connected = await webDavService.testConnection();
              if (connected) {
                await settings.setWebDavConfig(
                  baseUrl: baseUrlCtrl.text,
                  username: usernameCtrl.text,
                  password: passwordCtrl.text,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l10n.tr('webdav_saved'))),
                  );
                }
              } else {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l10n.tr('webdav_connect_failed'))),
                  );
                }
              }
            },
            child: Text(l10n.tr('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _syncAllToWebDav(BuildContext context, L10n l10n) async {
    final settings = context.read<SettingsProvider>();
    final prov = context.read<MemeProvider>();

    if (settings.webDavBaseUrl == null || settings.webDavUsername == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('webdav_not_configured'))),
      );
      return;
    }

    // 显示同步进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.tr('syncing')),
              ],
            ),
          ),
        ),
      ),
    );

    await prov.syncAllToWebDav();

    if (context.mounted) {
      Navigator.pop(context); // 关闭对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('sync_complete'))),
      );
    }
  }

  /// 查看更新日志：从 GitHub Releases 拉取并展示
  Future<void> _showChangelog(BuildContext context, L10n l10n) async {
    // 先弹出加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(l10n.tr('loading')),
          ],
        ),
      ),
    );

    final releases = await UpdateService().fetchChangelog();

    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭加载对话框

    if (releases.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('changelog_load_failed'))),
      );
      return;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.tr('changelog')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: releases.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (c, i) {
              final r = releases[i];
              return ExpansionTile(
                initiallyExpanded: i == 0,
                title: Text('v${r.version}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_formatDate(r.publishedAt), style: const TextStyle(fontSize: 11)),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        r.body.isEmpty ? r.name : r.body,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

class _ColorWheel extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  const _ColorWheel({required this.initialColor, required this.onColorChanged});

  @override
  State<_ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<_ColorWheel> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  /// 将本地坐标转换为 HSV（hue 0-360, saturation 0-1）
  /// 仅在圆形范围内有效，超出半径则饱和度截断为 1
  void _updateFromLocal(Offset localPos) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    // 角度：0 度在顶部（12 点方向），顺时针递增
    var angle = atan2(dx, -dy) * 180 / pi;
    if (angle < 0) angle += 360;
    final saturation = (dist / radius).clamp(0.0, 1.0);
    setState(() {
      _hsv = HSVColor.fromAHSV(1.0, angle, saturation, _hsv.value);
      widget.onColorChanged(_hsv.toColor());
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          onPanDown: (d) => _updateFromLocal(d.localPosition),
          onPanUpdate: (d) => _updateFromLocal(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: _WheelPainter(
              hsv: _hsv,
              radius: size.width / 2,
            ),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  final double radius;
  _WheelPainter({required this.hsv, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 用 SweepGradient 绘制色相环（圆盘），颜色从顶部开始顺时针
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          HSVColor.fromAHSV(1.0, 0, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 60, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 120, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 180, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 240, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 300, 1.0, 1.0).toColor(),
          HSVColor.fromAHSV(1.0, 360, 1.0, 1.0).toColor(),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // 叠加径向白色渐变实现饱和度（中心白→边缘饱和）
    final satPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, satPaint);

    // 选中指示器：在色轮上的位置
    final angleRad = hsv.hue * pi / 180;
    final indicatorDist = hsv.saturation * radius;
    final indicatorPos = Offset(
      center.dx + indicatorDist * sin(angleRad),
      center.dy - indicatorDist * cos(angleRad),
    );
    // 外圈白边
    canvas.drawCircle(
      indicatorPos,
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    // 内圈当前色
    canvas.drawCircle(
      indicatorPos,
      9,
      Paint()
        ..color = hsv.toColor()
        ..style = PaintingStyle.fill,
    );
    // 描边
    canvas.drawCircle(
      indicatorPos,
      9,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return oldDelegate.hsv != hsv;
  }
}
