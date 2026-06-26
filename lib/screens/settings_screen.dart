import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import '../providers/meme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../services/webdav_service.dart';
import '../services/auth_service.dart';
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
          _languageTile(context),
          const Divider(indent: 16, endIndent: 16),
          _themeModeTile(settings),
          const Divider(indent: 16, endIndent: 16),
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            _monetTile(settings),
            if (!settings.useMonet) ...[
              const SizedBox(height: 8),
              _presetPicker(settings, cs),
            ],
          ] else ...[
            const SizedBox(height: 8),
            _presetPicker(settings, cs),
          ],
          const SizedBox(height: 16),

          _sectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('批量导入'),
            subtitle: const Text('从 ZIP 恢复数据或导入图片'),
            onTap: () => _importZip(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出数据'),
            subtitle: const Text('导出所有表情包和元数据到 ZIP'),
            onTap: () => _exportData(context),
          ),
          const SizedBox(height: 16),

          _sectionHeader('云同步'),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: const Text('启用 WebDAV 同步'),
            subtitle: const Text('将表情包上传到 WebDAV 服务器'),
            value: settings.useWebDav,
            onChanged: (v) => settings.setUseWebDav(v),
          ),
          if (settings.useWebDav) ...[
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('WebDAV 配置'),
              subtitle: Text(settings.webDavBaseUrl != null ? '已配置' : '未配置'),
              onTap: () => _showWebDavConfigDialog(context),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('同步所有数据'),
              subtitle: const Text('将所有本地表情包上传到 WebDAV'),
              onTap: () => _syncAllToWebDav(context),
            ),
          ],
          const SizedBox(height: 16),

          _sectionHeader('用户认证'),
          SwitchListTile(
            secondary: const Icon(Icons.security_outlined),
            title: const Text('启用用户认证'),
            subtitle: const Text('支持多用户切换和权限控制'),
            value: settings.useUserAuth,
            onChanged: (v) => settings.setUseUserAuth(v),
          ),
          if (settings.useUserAuth) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('当前用户'),
              subtitle: Text(settings.currentUserId ?? '未登录'),
              onTap: () => _showUserAuthDialog(context),
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('切换用户'),
              onTap: () => _showUserAuthDialog(context),
            ),
          ],
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

  Widget _languageTile(BuildContext context) {
    final localeProv = context.watch<LocaleProvider>();
    final currentLang = localeProv.locale.languageCode;
    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text('语言'),
      trailing: DropdownButton<String>(
        value: currentLang,
        underline: const SizedBox(),
        items: const [
          DropdownMenuItem(value: 'zh', child: Text('简体中文')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (val) {
          if (val != null) {
            localeProv.setLocale(Locale(val));
          }
        },
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
      subtitle: const Text('Android 12+ 系统取色；其他平台自动使用配色方案'),
      value: settings.useMonet,
      onChanged: (v) => settings.setUseMonet(v),
    );
  }

  Widget _presetPicker(SettingsProvider settings, ColorScheme cs) {
    final presets = AppTheme.presets;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '配色方案',
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
          _customPresetCard(settings, cs),
        ],
      ),
    );
  }

  Widget _presetCard(ColorSchemePreset preset, bool selected, ColorScheme cs, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: cs.primary, width: 2) : null,
          color: selected ? cs.primaryContainer.withValues(alpha: 0.15) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: preset.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                preset.primary,
                if (preset.surfaceContainerHighest != null) preset.surfaceContainerHighest!,
                preset.secondary,
                preset.tertiary,
              ].map((c) {
                return Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.3), width: 0.5),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(preset.name, style: const TextStyle(fontSize: 14))),
            if (selected) Icon(Icons.check_circle, color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _customPresetCard(SettingsProvider settings, ColorScheme cs) {
    final selected = settings.presetIndex >= AppTheme.presets.length;
    return InkWell(
      onTap: () => _showCustomColorPicker(context, settings, cs),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: cs.onSurface, width: 2) : null,
          color: selected ? cs.surfaceContainerHighest.withValues(alpha: 0.3) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.edit, size: 18, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(selected ? '自定义 (已保存)' : '自定义配色方案', style: const TextStyle(fontSize: 14))),
            if (selected) Icon(Icons.check_circle, color: cs.primary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showCustomColorPicker(BuildContext context, SettingsProvider settings, ColorScheme cs) {
    final primaryCtrl = TextEditingController(
      text: '#${settings.customPrimary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
    final secondaryCtrl = TextEditingController(
      text: '#${settings.customSecondary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
    final tertiaryCtrl = TextEditingController(
      text: '#${settings.customTertiary.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );

    Color currentColor = settings.customPrimary;
    int editingIndex = 0;

    void setColor(Color c) {
      currentColor = c;
      if (editingIndex == 0) primaryCtrl.text = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
      if (editingIndex == 1) secondaryCtrl.text = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
      if (editingIndex == 2) tertiaryCtrl.text = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }

    setColor(settings.customPrimary);

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
              Row(
                children: [
                  Expanded(
                    child: _colorTab('主色', editingIndex == 0, () {
                      setModalState(() => setColor(currentColor));
                      setModalState(() => editingIndex = 0);
                      setModalState(() => currentColor = settings.customPrimary);
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _colorTab('辅助色', editingIndex == 1, () {
                      setModalState(() => editingIndex = 1);
                      setModalState(() => currentColor = settings.customSecondary);
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _colorTab('强调色', editingIndex == 2, () {
                      setModalState(() => editingIndex = 2);
                      setModalState(() => currentColor = settings.customTertiary);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 240,
                height: 240,
                child: _ColorWheel(
                  initialColor: currentColor,
                  onColorChanged: (c) {
                    setModalState(() => setColor(c));
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('明度', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
              Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: TextField(
                      controller: editingIndex == 0 ? primaryCtrl : (editingIndex == 1 ? secondaryCtrl : tertiaryCtrl),
                      maxLength: 9,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        prefixText: '#',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        hintText: 'HEX',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final hex = v.replaceAll('#', '');
                        if (hex.length == 8) {
                          final parsed = int.tryParse(hex, radix: 16);
                          if (parsed != null) {
                            setModalState(() => setColor(Color(parsed)));
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(bCtx),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child:                   FilledButton(
                      onPressed: () {
                        settings.setCustomColors(
                          editingIndex == 0 ? currentColor : settings.customPrimary,
                          editingIndex == 1 ? currentColor : settings.customSecondary,
                          editingIndex == 2 ? currentColor : settings.customTertiary,
                        );
                        Navigator.pop(bCtx);
                      },
                      child: const Text('保存'),
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

  Widget _colorTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        )),
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

  Future<void> _importZip(BuildContext ctx) async {
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
        title: const Text('导入数据'),
        content: Text('是否从 ${zipFile.name} 导入？\n\n如果 ZIP 包含 memes.json，将覆盖当前所有数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('导入')),
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
        msg = '备份导入成功';
      } else if (count > 0) {
        msg = '导入了 $count 张图片';
      } else {
        msg = '导入失败：无法识别的 ZIP 文件';
      }
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _checkUpdate(BuildContext ctx) async {
    setState(() => _checking = true);
    final service = UpdateService();
    final info = await service.check();
    if (!ctx.mounted) return;
    setState(() => _checking = false);

    if (info == null) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
      return;
    }

    if (!ctx.mounted) return;
    final result = await showDialog<bool>(
      context: ctx,
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

  void _showWebDavConfigDialog(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final baseUrlCtrl = TextEditingController(text: settings.webDavBaseUrl ?? '');
    final usernameCtrl = TextEditingController(text: settings.webDavUsername ?? '');
    final passwordCtrl = TextEditingController(text: settings.webDavPassword ?? '');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
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
                    const SnackBar(content: Text('WebDAV 配置保存成功')),
                  );
                }
              } else {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('连接失败，请检查配置')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncAllToWebDav(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final prov = context.read<MemeProvider>();
    
    if (settings.webDavBaseUrl == null || settings.webDavUsername == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置 WebDAV')),
      );
      return;
    }
    
    // 显示同步进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在同步到 WebDAV...'),
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
        const SnackBar(content: Text('同步完成')),
      );
    }
  }

  void _showUserAuthDialog(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final authService = AuthService();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('用户认证'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final success = await authService.register(
                          usernameCtrl.text,
                          passwordCtrl.text,
                        );
                        if (success && ctx.mounted) {
                          await settings.setCurrentUserId(usernameCtrl.text);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('注册成功')),
                          );
                        } else if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('注册失败，用户名可能已存在')),
                          );
                        }
                      },
                      child: const Text('注册'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final success = await authService.login(
                          usernameCtrl.text,
                          passwordCtrl.text,
                        );
                        if (success && ctx.mounted) {
                          await settings.setCurrentUserId(usernameCtrl.text);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('登录成功')),
                          );
                        } else if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('登录失败，请检查用户名和密码')),
                          );
                        }
                      },
                      child: const Text('登录'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
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
  Offset _selectedOffset = const Offset(0, -1);
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _selectedOffset = _colorToOffset(widget.initialColor);
  }

  Offset _colorToOffset(Color color) {
    final hsl = HSLColor.fromColor(color);
    final hue = hsl.hue;
    final sat = hsl.saturation;
    final angle = (hue * pi / 180) - pi / 2;
    return Offset(
      cos(angle) * sat,
      sin(angle) * sat,
    );
  }

  Color _offsetToColor(Offset offset, double lightness) {
    final distance = offset.distance;
    final angle = atan2(offset.dy, offset.dx);
    final saturation = min(distance, 1.0);
    final hue = ((angle + pi / 2) * 180 / pi) % 360;
    return HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.globalToLocal(details.globalPosition);
    final dx = (offset.dx / box.size.width) * 2 - 1;
    final dy = (offset.dy / box.size.height) * 2 - 1;
    final clampedDx = max(-1.0, min(1.0, dx));
    final clampedDy = max(-1.0, min(1.0, dy));
    setState(() {
      _selectedOffset = Offset(clampedDx, clampedDy);
      _currentColor = _offsetToColor(_selectedOffset, HSLColor.fromColor(_currentColor).lightness);
    });
    widget.onColorChanged(_currentColor);
  }

  void _handlePanDown(DragDownDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.globalToLocal(details.localPosition);
    final dx = (offset.dx / box.size.width) * 2 - 1;
    final dy = (offset.dy / box.size.height) * 2 - 1;
    setState(() {
      _selectedOffset = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
      _currentColor = _offsetToColor(_selectedOffset, HSLColor.fromColor(_currentColor).lightness);
    });
    widget.onColorChanged(_currentColor);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: _handlePanUpdate,
      onPanDown: _handlePanDown,
      child: CustomPaint(
        size: const Size(240, 240),
        painter: _WheelPainter(
          selectedOffset: _selectedOffset,
          currentColor: _currentColor,
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Offset selectedOffset;
  final Color currentColor;
  _WheelPainter({required this.selectedOffset, required this.currentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..strokeWidth = radius * 0.6
      ..style = PaintingStyle.fill;

    for (double angle = 0; angle < 360; angle += 2) {
      final startAngle = (angle - 90) * pi / 180;
      final endAngle = (angle - 90 + 2.5) * pi / 180;
      final hsl = HSLColor.fromAHSL(1.0, angle, 1.0, 0.5);
      paint.color = hsl.toColor();
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle,
        true,
        paint,
      );
    }

    canvas.drawCircle(
      center + Offset(selectedOffset.dx * radius * 0.9, selectedOffset.dy * radius * 0.9),
      10,
      Paint()
        ..color = currentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..colorFilter = ColorFilter.mode(currentColor.withValues(alpha: 0.8), BlendMode.srcATop),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return oldDelegate.selectedOffset != selectedOffset || oldDelegate.currentColor != currentColor;
  }
}
