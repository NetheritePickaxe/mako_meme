import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/storage_service.dart';
import 'services/share_receiver_service.dart';
import 'providers/meme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/locale_provider.dart';
import 'services/admin_service.dart';
import 'services/image_tool_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigLoader.load();
  final storage = StorageService();
  await storage.init();
  final localeProvider = LocaleProvider();
  await localeProvider.init();

  // 接收外部分享（仅 Android/iOS 生效）
  final shareReceiver = ShareReceiverService();

  // 单例 SettingsProvider：MemeProvider 内部依赖与 UI 共用同一份
  final settings = SettingsProvider(storage);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) {
          final prov = MemeProvider(storage, settings);
          // 分享回调：直接走导入流程
          shareReceiver.onShared = (files) {
            prov.importFiles(
              files,
              autoClassify: settings.autoClassify,
              classifyRatio: settings.classifyRatio,
            );
          };
          prov.init();
          // 监听初始/运行时分享 intent
          shareReceiver.init();
          return prov;
        }),
        Provider.value(value: storage),
        Provider.value(value: AdminService()),
        Provider.value(value: ImageToolService(storage)),
      ],
      child: const MakoMemeApp(),
    ),
  );
}

class MakoMemeApp extends StatelessWidget {
  const MakoMemeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return Consumer<SettingsProvider>(
          builder: (ctx, s, _) {
            final monetSeed = lightDynamic?.primary;
            final useMonet = s.useMonet && monetSeed != null;
            final seed = useMonet ? monetSeed : s.seedColor;
            final theme = AppTheme.light(seed);
            final darkTheme = AppTheme.dark(seed, pureBlack: s.pureBlack);
            return Consumer<LocaleProvider>(
              builder: (ctx, lp, _) {
                return MaterialApp(
                  title: 'Mako Meme',
                  debugShowCheckedModeBanner: false,
                  theme: theme,
                  darkTheme: darkTheme,
                  themeMode: s.themeMode,
                  locale: lp.locale,
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [
                    Locale('zh', 'cn'),
                    Locale('en', 'us'),
                  ],
                  home: const HomeScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}
