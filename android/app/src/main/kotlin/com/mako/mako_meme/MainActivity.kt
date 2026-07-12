package com.mako.mako_meme

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册原生插件：meme 索引导出给 ContentProvider
        flutterEngine.plugins.add(MemeIndexPlugin())
    }
}
