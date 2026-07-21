import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/l10n.dart';
import '../services/ime_status_service.dart';

/// 表情包输入法引导页：检测 IME / 无障碍服务状态，提供跳转设置入口。
/// 包含输入法切换按钮和测试输入框。
class KeyboardSetupScreen extends StatefulWidget {
  const KeyboardSetupScreen({super.key});

  @override
  State<KeyboardSetupScreen> createState() => _KeyboardSetupScreenState();
}

class _KeyboardSetupScreenState extends State<KeyboardSetupScreen> with WidgetsBindingObserver {
  bool _imeEnabled = false;
  bool _imeDefault = false;
  bool _a11yEnabled = false;
  bool _loading = true;
  final bool _isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置返回时刷新状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (!_isAndroid) {
      setState(() => _loading = false);
      return;
    }
    final ime = await ImeStatusService.isImeEnabled();
    final def = await ImeStatusService.isImeDefault();
    final a11y = await ImeStatusService.isAccessibilityEnabled();
    if (mounted) {
      setState(() {
        _imeEnabled = ime;
        _imeDefault = def;
        _a11yEnabled = a11y;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocaleProvider>().l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('keyboard_setup')),
        actions: [
          if (_isAndroid)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.tr('refresh'),
              onPressed: _refreshStatus,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : !_isAndroid
              ? _buildUnavailable(l10n, cs)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 输入法状态
                    _buildStatusCard(
                      l10n.tr('keyboard_setup'),
                      l10n.tr('keyboard_setup_desc'),
                      _imeEnabled,
                      _imeEnabled
                          ? (_imeDefault
                              ? l10n.tr('ime_is_default')
                              : l10n.tr('ime_not_default'))
                          : l10n.tr('ime_not_enabled'),
                      Icons.keyboard_outlined,
                      cs,
                      actionLabel: _imeEnabled ? l10n.tr('open_ime_settings') : l10n.tr('enable_ime'),
                      onAction: () => ImeStatusService.openImeSettings(),
                    ),
                    // 输入法已启用时显示「切换到本输入法」卡片（与上方状态卡片样式一致）
                    if (_imeEnabled) ...[
                      const SizedBox(height: 12),
                      _buildSwitchImeCard(l10n, cs),
                    ],
                    const SizedBox(height: 12),
                    // 无障碍状态
                    _buildStatusCard(
                      l10n.tr('enable_accessibility'),
                      l10n.tr('accessibility_desc'),
                      _a11yEnabled,
                      _a11yEnabled
                          ? l10n.tr('accessibility_enabled')
                          : l10n.tr('accessibility_not_enabled'),
                      Icons.accessibility_new_outlined,
                      cs,
                      actionLabel: l10n.tr('open_accessibility_settings'),
                      onAction: () => ImeStatusService.openAccessibilitySettings(),
                    ),
                    const SizedBox(height: 16),
                    // 使用说明
                    _buildInstructions(l10n, cs),
                  ],
                ),
    );
  }

  /// 「切换到本输入法」卡片：样式与上方状态卡片一致
  Widget _buildSwitchImeCard(L10n l10n, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tr('switch_to_ime'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(l10n.tr('switch_to_ime_desc'),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () async {
                  await ImeStatusService.showImePicker();
                  if (mounted) _refreshStatus();
                },
                child: Text(l10n.tr('switch_to_ime')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailable(L10n l10n, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.desktop_access_disabled, size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(l10n.tr('keyboard_feature_unavailable'),
                style: TextStyle(color: cs.outline), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    String title,
    String subtitle,
    bool enabled,
    String statusText,
    IconData icon,
    ColorScheme cs, {
    required String actionLabel,
    required Future<bool> Function() onAction,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: enabled ? cs.primary : cs.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.check_circle : Icons.error_outline,
                  color: enabled ? Colors.green : cs.error,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (enabled ? cs.primary : cs.error).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? cs.primary : cs.error,
                    fontWeight: FontWeight.w500,
                  )),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () async {
                  await onAction();
                  // 从系统设置返回后立即刷新状态
                  if (mounted) _refreshStatus();
                },
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions(L10n l10n, ColorScheme cs) {
    final steps = [
      '${l10n.tr('enable_ime')} → ${l10n.tr('enable_accessibility')}',
      '在任意聊天 App 中切换到「Mako 表情包输入法」',
      '点击表情包选中，再点「无障碍发送」自动发送到微信/QQ',
      '或点「分享发送」用系统分享面板发送',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('使用步骤', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 12),
            ...steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(right: 10, top: 1),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text('${e.key + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer)),
                      ),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
