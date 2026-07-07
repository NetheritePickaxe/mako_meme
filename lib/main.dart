import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/storage_service.dart';
import 'providers/meme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/locale_provider.dart';
import 'services/admin_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigLoader.load();
  final storage = StorageService();
  await storage.init();
  final localeProvider = LocaleProvider();
  await localeProvider.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider(create: (_) => MemeProvider(storage, SettingsProvider(storage))..init()),
        ChangeNotifierProvider(create: (_) => SettingsProvider(storage)),
        Provider.value(value: storage),
        Provider.value(value: AdminService()),
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
            final useMonet = s.useMonet && lightDynamic != null;
            final theme = useMonet
                ? AppTheme.light(lightDynamic.primary)
                : AppTheme.lightWithPreset(s.currentPreset);
            final darkTheme = useMonet
                ? AppTheme.dark(lightDynamic.primary, pureBlack: s.pureBlack)
                : AppTheme.darkWithPreset(s.currentPreset, pureBlack: s.pureBlack);
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
