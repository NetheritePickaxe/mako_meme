import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'presentation/screens/home_screen.dart';

class MakoMemeApp extends StatelessWidget {
  const MakoMemeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mako Meme',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
