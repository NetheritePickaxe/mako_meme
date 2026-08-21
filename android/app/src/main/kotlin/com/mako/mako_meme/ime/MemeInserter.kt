package com.mako.mako_meme.ime

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.view.inputmethod.EditorInfoCompat
import androidx.core.view.inputmethod.InputConnectionCompat
import androidx.core.view.inputmethod.InputContentInfoCompat
import java.io.File
import java.io.FileInputStream

/**
 * 表情包直接插入当前聊天输入框的策略层。
 *
 * 发送优先级（fallback chain）：
 * - 文字类 meme → commitText() 直接上屏（所有 App 通用）
 * - 图片类 + 编辑器声明支持 image mime（非密码/数字框）→ commitContent() 直插
 *   （适用于 Telegram / WhatsApp / Signal / Google Messages 等声明 contentMimeTypes 的 App）
 * - 图片类 + 前台 App 是微信（packageName == com.tencent.mm）→ MediaStore 复制到公共
 *   Pictures/mako_meme_temp/{id}.{ext} → commitText(绝对路径) 上屏；微信输入框会自动识别路径
 *   并弹出发图确认框，GIF 会被自动转换成动态表情
 * - 其他情况（含 QQ / 不支持的 App）→ false，由调用方回退系统分享面板
 *
 * 参考：搜狗输入法微信斗图方案（2017）、Android Image Keyboard Support API
 */
object MemeInserter {

    private const val TAG = "MemeInserter"
    private const val FILE_PROVIDER_AUTHORITY = "com.mako.mako_meme.fileprovider"
    private const val TEMP_DIR_RELATIVE = "mako_meme_temp"

    /**
     * 尝试将 [meme] 直接插入当前聚焦的聊天输入框。
     * 成功返回 true；失败返回 false（调用方应回退系统分享面板）。
     */
    fun tryInsert(
        context: Context,
        meme: MemeItem,
        inputConnection: android.view.inputmethod.InputConnection?,
        editorInfo: android.view.inputmethod.EditorInfo?,
    ): Boolean {
        if (inputConnection == null || editorInfo == null) return false

        // 1. 文字类：直接 commitText
        if (!meme.isImage) {
            val text = meme.textContent?.takeIf { it.isNotBlank() } ?: meme.name
            inputConnection.commitText(text, 1)
            Log.d(TAG, "已 commitText: $text")
            return true
        }

        // 2. 编辑器声明支持图片 mime 且非密码/数字框 → commitContent
        if (canCommitContent(editorInfo)) {
            val uri = runCatching {
                FileProvider.getUriForFile(context, FILE_PROVIDER_AUTHORITY, File(meme.absPath))
            }.getOrNull() ?: return false
            val mime = meme.mimeType.ifEmpty { "image/*" }
            val inputContentInfo = InputContentInfoCompat(
                uri,
                android.content.ClipDescription("meme", arrayOf(mime)),
                null
            )
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                InputConnectionCompat.INPUT_CONTENT_GRANT_READ_URI_PERMISSION
            } else 0
            val done = InputConnectionCompat.commitContent(
                inputConnection, editorInfo, inputContentInfo, flags, null
            )
            if (done) {
                Log.d(TAG, "commitContent 成功 (mime=$mime)")
                return true
            }
            Log.w(TAG, "commitContent 返回 false，回退")
        }

        // 3. 微信专属路径上屏
        if (isWeChat(editorInfo)) {
            return commitImagePath(context, meme, inputConnection)
        }

        // 4. 其他 App 不支持直接插入
        return false
    }

    private fun canCommitContent(editorInfo: android.view.inputmethod.EditorInfo): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return false
        val inputType = editorInfo.inputType
        // 密码 / 数字 / 电话 / 日期时间输入框不处理富文本
        // TYPE_CLASS_MASK / TYPE_TEXT_VARIATION_MASK 非公开常量，使用 SDK 内联值（低 4 位 / 次低 4 位）
        val classMask = 0x0000000f
        val variationMask = 0x000000f0
        if ((inputType and classMask) == android.text.InputType.TYPE_CLASS_NUMBER ||
            (inputType and classMask) == android.text.InputType.TYPE_CLASS_PHONE
        ) return false
        if ((inputType and variationMask) == android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD) return false
        // 编辑器未声明支持的 mime 类型 → 不尝试（避免无效的 commitContent 调用）
        val mimes = EditorInfoCompat.getContentMimeTypes(editorInfo)
        return mimes.isNotEmpty() && mimes.any { it.startsWith("image/") }
    }

    private fun isWeChat(editorInfo: android.view.inputmethod.EditorInfo): Boolean =
        editorInfo.packageName == "com.tencent.mm"

    /** 将图片复制到公共存储后，commitText 图片绝对路径，微信输入框会识别并弹出发图确认框。 */
    private fun commitImagePath(
        context: Context,
        meme: MemeItem,
        ic: android.view.inputmethod.InputConnection,
    ): Boolean {
        val absPath = copyToPublicTemp(context, meme) ?: run {
            Log.e(TAG, "复制到公共目录失败: ${meme.absPath}")
            return false
        }
        ic.commitText(absPath, 1)
        Log.d(TAG, "微信路径上屏: $absPath")
        return true
    }

    /** 把 [meme] 对应的图片写入公共 Pictures/mako_meme_temp/{id}.{ext}，返回 MediaStore DATA 列路径。 */
    private fun copyToPublicTemp(context: Context, meme: MemeItem): String? {
        val srcFile = File(meme.absPath)
        if (!srcFile.exists()) {
            Log.e(TAG, "源图片不存在: ${meme.absPath}")
            return null
        }
        val ext = srcFile.extension.ifEmpty { "jpg" }
        val displayName = "${meme.id}.$ext"
        val mimeType = when (ext.lowercase()) {
            "gif" -> "image/gif"
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
        val resolver = context.contentResolver
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        // 删除同名旧条目，避免重复堆积
        resolver.query(
            collection,
            arrayOf(MediaStore.Images.Media._ID),
            "${MediaStore.Images.Media.DISPLAY_NAME} = ?",
            arrayOf(displayName),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                resolver.delete(Uri.withAppendedPath(collection, id.toString()), null, null)
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$TEMP_DIR_RELATIVE")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: return null
        var path: String? = null
        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(srcFile).use { it.copyTo(out) }
            }
            val finalizeValues = ContentValues()
            finalizeValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, finalizeValues, null, null)
            resolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.DATA),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) path = cursor.getString(0)
            }
            if (path != null) Log.d(TAG, "MediaStore 写入成功: $path")
        } catch (e: Exception) {
            Log.e(TAG, "写入 MediaStore 失败", e)
        }
        return path
    }
}
