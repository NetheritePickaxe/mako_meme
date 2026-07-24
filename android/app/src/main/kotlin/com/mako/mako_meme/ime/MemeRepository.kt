package com.mako.mako_meme.ime

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import net.sourceforge.pinyin4j.PinyinHelper
import java.util.Locale

/**
 * 通过 [MemeContentProvider] 读取 meme 数据。
 *
 * - [loadMemes] 异步查询 content://com.mako.mako_meme.memes/memes，解析 JSON 后回调主线程。
 * - [search] 在内存中对已加载列表做本地过滤（按 name / pinyin / tags / textContent 包含匹配）。
 *
 * 用 [HandlerThread] 执行后台查询，避免阻塞 IME 主线程。
 */
class MemeRepository(context: Context) {

    companion object {
        private const val AUTHORITY = "com.mako.mako_meme.memes"
        private val URI_MEMES: Uri = Uri.parse("content://$AUTHORITY/memes")
        private const val COLUMN_JSON = "json"
        private const val TAG = "MemeRepository"
    }

    private val appContext = context.applicationContext

    private val handlerThread = HandlerThread("MemeRepo").apply { start() }
    private val workHandler = Handler(handlerThread.looper)

    /**
     * 异步加载全部 meme。回调始终在主线程触发。
     */
    fun loadMemes(callback: (List<MemeItem>) -> Unit) {
        workHandler.post {
            val list = queryMemes().map { item ->
                item.withPinyin(toPinyin(item.name), item.tags.map { toPinyin(it) })
            }
            Handler(appContext.mainLooper).post { callback(list) }
        }
    }

    /** 查询 ContentProvider 并解析为 [List<MemeItem>]。失败返回空列表。 */
    private fun queryMemes(): List<MemeItem> {
        return runCatching {
            val cursor = appContext.contentResolver.query(
                URI_MEMES,
                arrayOf(COLUMN_JSON),
                null,
                null,
                null
            ) ?: return emptyList()

            cursor.use { c ->
                if (!c.moveToFirst()) return emptyList()
                val idx = c.getColumnIndexOrThrow(COLUMN_JSON)
                val json = c.getString(idx)
                MemeItem.fromJson(json)
            }
        }.getOrElse {
            Log.e(TAG, "查询 meme 数据失败", it)
            emptyList()
        }
    }

    /**
     * 本地过滤：按 [query] 在 [list] 中匹配 name / pinyin / tags / textContent（大小写不敏感）。
     * 支持拼音搜索：查询词自动转拼音后匹配 pinyinName / pinyinTags。
     * query 为空白时原样返回。
     */
    fun search(query: String, list: List<MemeItem>): List<MemeItem> {
        if (query.isBlank()) return list
        val q = query.trim().lowercase(Locale.ROOT)
        val qPinyin = toPinyin(q)
        return list.filter { item ->
            item.name.lowercase(Locale.ROOT).contains(q) ||
                    item.pinyinName.contains(q) ||
                    item.pinyinName.contains(qPinyin) ||
                    item.tags.any { it.lowercase(Locale.ROOT).contains(q) } ||
                    item.pinyinTags.any { it.contains(q) || it.contains(qPinyin) } ||
                    (item.textContent?.lowercase(Locale.ROOT)?.contains(q) == true)
        }
    }

    /** 将中文转为拼音（不带声调），非中文原样保留。 */
    private fun toPinyin(input: String): String {
        val sb = StringBuilder()
        for (ch in input) {
            val pinyins = PinyinHelper.toHanyuPinyinStringArray(ch)
            if (pinyins != null && pinyins.isNotEmpty()) {
                sb.append(pinyins[0].replace(Regex("[0-9]"), ""))
            } else {
                sb.append(ch)
            }
        }
        return sb.toString().lowercase(Locale.ROOT)
    }

    /** 释放后台线程，应在 Service onDestroy 时调用。 */
    fun release() {
        handlerThread.quitSafely()
    }
}
