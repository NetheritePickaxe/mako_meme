import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import '../providers/meme_provider.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader('外观'),
          _themeModeTile(settings),
          const Divider(indent: 16, endIndent: 16),
          _monetTile(settings),
          if (!settings.useMonet) ...[
            const SizedBox(height: 8),
            _colorPicker(settings, cs),
          ],
          const SizedBox(height: 16),

          _sectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出数据'),
            subtitle: const Text('备份所有表情包和元数据'),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入备份'),
            subtitle: const Text('恢复备份或导入图片 ZIP'),
            onTap: () => _importZip(context),
          ),
          const SizedBox(height: 16),

          _sectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('1.0.0+1'),
          ),
          ListTile(
            leading: Icon(_checking ? Icons.hourglass_top : Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: const Text('查看 GitHub 最新版本'),
            onTap: _checking ? null : () => _checkUpdate(context),
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

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _themeModeTile(SettingsProvider settings) {
    return ListTile(
      leading: const Icon(Icons.brightness_6),
      title: const Text('主题模式'),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('系统')),
          ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
          ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
        ],
        selected: {settings.themeMode},
        onSelectionChanged: (v) => settings.setThemeMode(v.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _monetTile(SettingsProvider settings) {
    return SwitchListTile(
      secondary: const Icon(Icons.palette_outlined),
      title: const Text('使用莫奈取色'),
      subtitle: const Text('Android 12+ 系统动态配色'),
      value: settings.useMonet,
      onChanged: (v) => settings.setUseMonet(v),
    );
  }

  Widget _colorPicker(SettingsProvider settings, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: AppTheme.presetColors.map((c) {
          final selected = c.toARGB32() == settings.accentColor.toARGB32();
          return GestureDetector(
            onTap: () => settings.setAccentColor(c.toARGB32()),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: cs.onSurface, width: 3)
                    : null,
              ),
              child: selected
                  ? Icon(Icons.check, color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 20)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    final storage = context.read<StorageService>();
    final path = await storage.exportData();
    if (path == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败')),
        );
      }
      return;
    }

    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web 端不支持导出')),
        );
      }
      return;
    }

    final file = File(path);
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '保存备份',
      fileName: 'mako_meme_backup.zip',
      type: FileType.any,
    );
    if (saved != null) {
      await file.copy(saved);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出成功')),
        );
      }
    }
    await file.delete();
  }

  Future<void> _importZip(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;

    final zipFile = result.files.first;
    if (zipFile.path == null) return;

    final storage = context.read<StorageService>();
    final prov = context.read<MemeProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份'),
        content: Text('是否从 ${zipFile.name} 导入？\n\n如果 ZIP 包含 memes.json，将覆盖当前所有数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );
    if (confirmed != true) return;

    final count = await storage.importZip(zipFile.path!);
    await prov.loadAll();

    if (context.mounted) {
      String msg;
      if (count == 0) msg = '备份导入成功';
      else if (count > 0) msg = '导入了 $count 张图片';
      else msg = '导入失败：无法识别的 ZIP 文件';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _checkUpdate(BuildContext context) async {
    setState(() => _checking = true);
    final service = UpdateService();
    final info = await service.check();
    if (!mounted) return;
    setState(() => _checking = false);

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('版本 $info.version 可用，是否下载？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍后')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('下载')),
        ],
      ),
    );
    if (result == true) {
      await UpdateService.openUrl(info.downloadUrl);
    }
  }
}
