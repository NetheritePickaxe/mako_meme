package com.mako.mako_meme.ime

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * 从 filesDir/ime_theme.json 读取主应用同步的主题配色。
 *
 * 文件由 [com.mako.mako_meme.MemeIndexPlugin] 的 `updateImeTheme` 方法写入。
 * IME 在 [MakoImeService.onCreateInputView] 时读取，应用与主应用一致的配色。
 *
 * 字段语义（参考 Gboard / Rime 配色规范）：
 * - [bg]           键盘底色
 * - [surface]      顶栏 / 工具栏底色（比 bg 略浅）
 * - [cardBg]       网格单元格底色
 * - [keyBg]        按键默认底色
 * - [keyActiveBg]  按键按下 / 选中态底色（accent 半透明）
 * - [keyFuncBg]    功能键（退格 / 空格 / 完成 / 切换）底色
 * - [accent]       主题强调色
 * - [onAccent]     accent 上的前景色
 * - [text]         主文字色
 * - [subText]      次要文字色（hint / 未选 Tab）
 * - [tabBg]        选中 Tab 背景色
 * - [tabText]      选中 Tab 文字色
 * - [divider]      分割线色
 */
data class ImeTheme(
    val dark: Boolean,
    val bg: Int,
    val surface: Int,
    val cardBg: Int,
    val keyBg: Int,
    val keyActiveBg: Int,
    val keyFuncBg: Int,
    val accent: Int,
    val onAccent: Int,
    val text: Int,
    val subText: Int,
    val tabBg: Int,
    val tabText: Int,
    val divider: Int,
) {
    companion object {
        private const val THEME_FILE = "ime_theme.json"

        /** 默认深色主题（文件不存在或解析失败时使用）。 */
        val DEFAULT_DARK = ImeTheme(
            dark = true,
            bg = 0xFF161616.toInt(),
            surface = 0xFF1F1F1F.toInt(),
            cardBg = 0xFF242424.toInt(),
            keyBg = 0xFF3A3A3A.toInt(),
            keyActiveBg = 0xFF6366F1.toInt(),
            keyFuncBg = 0xFF2A2A2A.toInt(),
            accent = 0xFF6366F1.toInt(),
            onAccent = 0xFFFFFFFF.toInt(),
            text = 0xFFEEEEEE.toInt(),
            subText = 0xFF9A9A9A.toInt(),
            tabBg = 0xFF6366F1.toInt(),
            tabText = 0xFFFFFFFF.toInt(),
            divider = 0xFF2E2E2E.toInt(),
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
                    cardBg = json.optLong("cardBg", DEFAULT_DARK.cardBg.toLong()).toInt(),
                    keyBg = json.optLong("keyBg", DEFAULT_DARK.keyBg.toLong()).toInt(),
                    keyActiveBg = json.optLong("keyActiveBg", DEFAULT_DARK.keyActiveBg.toLong()).toInt(),
                    keyFuncBg = json.optLong("keyFuncBg", DEFAULT_DARK.keyFuncBg.toLong()).toInt(),
                    accent = json.optLong("accent", DEFAULT_DARK.accent.toLong()).toInt(),
                    onAccent = json.optLong("onAccent", DEFAULT_DARK.onAccent.toLong()).toInt(),
                    text = json.optLong("text", DEFAULT_DARK.text.toLong()).toInt(),
                    subText = json.optLong("subText", DEFAULT_DARK.subText.toLong()).toInt(),
                    tabBg = json.optLong("tabBg", DEFAULT_DARK.tabBg.toLong()).toInt(),
                    tabText = json.optLong("tabText", DEFAULT_DARK.tabText.toLong()).toInt(),
                    divider = json.optLong("divider", DEFAULT_DARK.divider.toLong()).toInt(),
                )
            }.getOrElse { DEFAULT_DARK }
        }
    }
}
