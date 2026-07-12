package com.mako.mako_meme.ime

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * 从 filesDir/ime_theme.json 读取主应用同步的主题配色。
 *
 * 文件由 [com.mako.mako_meme.MemeIndexPlugin] 的 `updateImeTheme` 方法写入。
 * IME 在 [MakoImeService.onCreateInputView] 时读取，应用与主应用一致的配色。
 */
data class ImeTheme(
    val dark: Boolean,
    val bg: Int,
    val surface: Int,
    val accent: Int,
    val onAccent: Int,
    val text: Int,
    val subText: Int,
    val tabBg: Int,
    val tabText: Int,
) {
    companion object {
        private const val THEME_FILE = "ime_theme.json"

        /** 默认深色主题（文件不存在或解析失败时使用）。 */
        val DEFAULT_DARK = ImeTheme(
            dark = true,
            bg = 0xFF1A1A1A.toInt(),
            surface = 0xFF242424.toInt(),
            accent = 0xFF6366F1.toInt(),
            onAccent = 0xFFFFFFFF.toInt(),
            text = 0xFFEEEEEE.toInt(),
            subText = 0xFFAAAAAA.toInt(),
            tabBg = 0xFF6366F1.toInt(),
            tabText = 0xFFFFFFFF.toInt(),
        )

        /** 从 filesDir 读取主题文件。失败返回 [DEFAULT_DARK]。 */
        fun load(context: Context): ImeTheme {
            return runCatching {
                val file = File(context.filesDir, THEME_FILE)
                if (!file.exists()) return DEFAULT_DARK
                val json = JSONObject(file.readText())
                ImeTheme(
                    dark = json.optBoolean("dark", true),
                    bg = json.optLong("bg", DEFAULT_DARK.bg.toLong()).toInt(),
                    surface = json.optLong("surface", DEFAULT_DARK.surface.toLong()).toInt(),
                    accent = json.optLong("accent", DEFAULT_DARK.accent.toLong()).toInt(),
                    onAccent = json.optLong("onAccent", DEFAULT_DARK.onAccent.toLong()).toInt(),
                    text = json.optLong("text", DEFAULT_DARK.text.toLong()).toInt(),
                    subText = json.optLong("subText", DEFAULT_DARK.subText.toLong()).toInt(),
                    tabBg = json.optLong("tabBg", DEFAULT_DARK.tabBg.toLong()).toInt(),
                    tabText = json.optLong("tabText", DEFAULT_DARK.tabText.toLong()).toInt(),
                )
            }.getOrElse { DEFAULT_DARK }
        }
    }
}
