package com.mako.mako_meme

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 接收 Flutter 侧导出的 meme 索引，写入 filesDir/meme_index.json
 * 供 MemeContentProvider 读取。
 *
 * MethodChannel: mako_meme/native
 * 方法:
 *   updateMemeIndex(json: String) → Boolean  写入索引文件
 *   clearMemeIndex() → Boolean                删除索引文件
 *   isImeEnabled() → Boolean                  当前 IME 是否在系统输入法列表中启用
 *   isImeDefault() → Boolean                  当前 IME 是否为默认输入法
 *   isAccessibilityEnabled() → Boolean        无障碍服务是否已启用
 *   openImeSettings() → void                  跳转到系统输入法设置页
 *   openAccessibilitySettings() → void        跳转到系统无障碍设置页
 */
class MemeIndexPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "mako_meme/native"
        private const val INDEX_FILE = "meme_index.json"
        private const val TAG = "MemeIndexPlugin"

        /** 本应用的 IME 服务组件名（全限定）。 */
        private const val IME_FLATTENED = "com.mako.mako_meme/com.mako.mako_meme.ime.MakoImeService"
        /** 本应用的无障碍服务组件名。 */
        private const val A11Y_FLATTENED = "com.mako.mako_meme/com.mako.mako_meme.accessibility.MakoAccessibilityService"
    }

    private var context: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        when (call.method) {
            "updateMemeIndex" -> {
                if (ctx == null) { result.success(false); return }
                val json = call.argument<String>("json") ?: ""
                if (json.isEmpty()) { result.success(false); return }
                runCatching {
                    File(ctx.filesDir, INDEX_FILE).writeText(json)
                    Log.d(TAG, "Meme index updated: ${json.length} bytes")
                    result.success(true)
                }.getOrElse {
                    Log.e(TAG, "Failed to write index", it)
                    result.success(false)
                }
            }
            "clearMemeIndex" -> {
                if (ctx == null) { result.success(false); return }
                runCatching {
                    val f = File(ctx.filesDir, INDEX_FILE)
                    if (f.exists()) f.delete()
                    result.success(true)
                }.getOrElse { result.success(false) }
            }
            "isImeEnabled" -> {
                result.success(isImeEnabled(ctx))
            }
            "isImeDefault" -> {
                result.success(isImeDefault(ctx))
            }
            "isAccessibilityEnabled" -> {
                result.success(isAccessibilityEnabled(ctx))
            }
            "openImeSettings" -> {
                if (ctx == null) { result.success(false); return }
                runCatching {
                    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    ctx.startActivity(intent)
                    result.success(true)
                }.getOrElse { result.success(false) }
            }
            "openAccessibilitySettings" -> {
                if (ctx == null) { result.success(false); return }
                runCatching {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    ctx.startActivity(intent)
                    result.success(true)
                }.getOrElse { result.success(false) }
            }
            else -> result.notImplemented()
        }
    }

    /** 检查本应用 IME 是否已在系统输入法列表中启用。 */
    private fun isImeEnabled(ctx: Context?): Boolean {
        if (ctx == null) return false
        val imeIds = Settings.Secure.getString(
            ctx.contentResolver,
            Settings.Secure.ENABLED_INPUT_METHODS
        ) ?: return false
        return imeIds.split(";").any { it == IME_FLATTENED }
    }

    /** 检查本应用 IME 是否为当前默认输入法。 */
    private fun isImeDefault(ctx: Context?): Boolean {
        if (ctx == null) return false
        val defaultId = Settings.Secure.getString(
            ctx.contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD
        ) ?: return false
        return defaultId == IME_FLATTENED
    }

    /** 检查本应用无障碍服务是否已启用。 */
    private fun isAccessibilityEnabled(ctx: Context?): Boolean {
        if (ctx == null) return false
        val enabled = Settings.Secure.getString(
            ctx.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val colon = Char(58) // ':'
        val splitter = TextUtils.SimpleStringSplitter(colon)
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(A11Y_FLATTENED, ignoreCase = true)) return true
        }
        return false
    }
}

