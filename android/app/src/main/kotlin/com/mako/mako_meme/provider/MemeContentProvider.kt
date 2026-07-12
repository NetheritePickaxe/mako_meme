package com.mako.mako_meme.provider

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 暴露主 App 的 meme 数据给 IME 进程。
 *
 * URI:
 *   content://com.mako.mako_meme.memes/memes          → 返回所有 meme 的 JSON（单行单列 "json"）
 *   content://com.mako.mako_meme.memes/image/{id}      → 返回图片文件（openFile）
 *   content://com.mako.mako_meme.memes/text/{id}       → 返回文字 meme 的文本（单行单列 "text"）
 *
 * 数据来源：filesDir/meme_index.json（由 Flutter 侧通过 MethodChannel 写入）
 */
class MemeContentProvider : ContentProvider() {

    companion object {
        const val AUTHORITY = "com.mako.mako_meme.memes"
        const val PATH_MEMES = "memes"
        const val PATH_IMAGE = "image"
        const val PATH_TEXT = "text"

        private const val CODE_MEMES = 1
        private const val CODE_IMAGE = 2
        private const val CODE_TEXT = 3

        private const val TAG = "MemeProvider"
        private const val INDEX_FILE = "meme_index.json"
    }

    private lateinit var matcher: UriMatcher

    override fun onCreate(): Boolean {
        matcher = UriMatcher(UriMatcher.NO_MATCH).apply {
            addURI(AUTHORITY, PATH_MEMES, CODE_MEMES)
            addURI(AUTHORITY, "$PATH_IMAGE/*", CODE_IMAGE)
            addURI(AUTHORITY, "$PATH_TEXT/*", CODE_TEXT)
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        when (matcher.match(uri)) {
            CODE_MEMES -> {
                val json = readIndexJson() ?: return null
                val cursor = MatrixCursor(arrayOf("json"))
                cursor.addRow(arrayOf(json))
                return cursor
            }
            CODE_TEXT -> {
                val id = uri.lastPathSegment ?: return null
                val meme = findMemeById(id) ?: return null
                val text = meme.optString("textContent", "")
                val cursor = MatrixCursor(arrayOf("text"))
                cursor.addRow(arrayOf(text))
                return cursor
            }
        }
        return null
    }

    override fun getType(uri: Uri): String? {
        return when (matcher.match(uri)) {
            CODE_MEMES -> "vnd.android.cursor.dir/vnd.com.mako.mako_meme.memes"
            CODE_IMAGE -> "image/*"
            CODE_TEXT -> "text/plain"
            else -> null
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (matcher.match(uri) != CODE_IMAGE) return null
        val id = uri.lastPathSegment ?: return null
        val meme = findMemeById(id) ?: return null
        val absPath = meme.optString("absPath", "")
        if (absPath.isEmpty()) return null
        val file = File(absPath)
        if (!file.exists() || !file.isFile) {
            Log.w(TAG, "Image file not found: $absPath")
            return null
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    // ===== 内部工具 =====

    private fun indexFile(): File =
        File(context!!.filesDir, INDEX_FILE)

    private fun readIndexJson(): String? {
        val file = indexFile()
        if (!file.exists()) {
            Log.w(TAG, "Index file not found: ${file.absolutePath}")
            return null
        }
        return runCatching { file.readText() }.getOrElse {
            Log.e(TAG, "Failed to read index", it)
            null
        }
    }

    private fun findMemeById(id: String): JSONObject? {
        val json = readIndexJson() ?: return null
        return runCatching {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                if (obj.optString("id") == id) return obj
            }
            null
        }.getOrElse {
            Log.e(TAG, "Failed to parse index", it)
            null
        }
    }
}
