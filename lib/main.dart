import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'services/storage_service.dart';
import 'providers/meme_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MemeProvider(storage)..init()),
        ChangeNotifierProvider(create: (_) => SettingsProvider(storage)),
        Provider.value(value: storage),
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
            final seed = s.useMonet && lightDynamic != null
                ? lightDynamic.primary
                : s.accentColor;
            return MaterialApp(
              title: 'Mako Meme',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(seed),
              darkTheme: AppTheme.dark(seed),
              themeMode: s.themeMode,
              home: const HomeScreen(),
            );
          },
        );
      },
    );
  }
}
