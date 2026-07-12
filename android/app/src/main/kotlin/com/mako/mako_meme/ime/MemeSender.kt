package com.mako.mako_meme.ime

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * meme 发送策略（静态方法）。
 *
 * - [sendViaShare]：通过系统分享面板发送。图片用 FileProvider 暴露 content URI（targetSdk 36 不能用 file://），
 *   文字用 EXTRA_TEXT 发送。
 * - [sendViaAccessibility]：把 meme 信息写入 filesDir/pending_send.json，再发广播通知无障碍服务执行发送。
 */
object MemeSender {

    private const val TAG = "MemeSender"

    /** FileProvider authority，需与 AndroidManifest 中声明一致。 */
    private const val FILE_PROVIDER_AUTHORITY = "com.mako.mako_meme.fileprovider"

    /** 待发送 meme 的缓存文件名（写入 filesDir）。 */
    private const val PENDING_SEND_FILE = "pending_send.json"

    /** 通知无障碍服务执行发送的广播 action。 */
    const val ACTION_SEND_MEME = "com.mako.mako_meme.ACTION_SEND_MEME"

    /**
     * 通过系统分享发送 meme。
     * - 图片类：FileProvider 生成 content URI，FLAG_GRANT_READ_URI_PERMISSION，mimeType 为 image/*（或 meme 自带 mimeType）。
     * - 文字类：EXTRA_TEXT 发送 textContent。
     * - 始终加 FLAG_ACTIVITY_NEW_TASK（从 Service/非 Activity Context 启动需要）。
     */
    fun sendViaShare(context: Context, meme: MemeItem) {
        if (meme.isImage) {
            shareImage(context, meme)
        } else {
            shareText(context, meme)
        }
    }

    /** 通过系统分享发送图片。 */
    private fun shareImage(context: Context, meme: MemeItem) {
        val file = File(meme.absPath)
        if (!file.exists() || !file.isFile) {
            Log.w(TAG, "图片文件不存在: ${meme.absPath}")
            return
        }
        val uri: Uri = runCatching {
            FileProvider.getUriForFile(context, FILE_PROVIDER_AUTHORITY, file)
        }.getOrElse {
            Log.e(TAG, "FileProvider 获取 URI 失败，请检查 manifest 配置", it)
            return
        }

        val mime = meme.mimeType.takeIf { it.isNotBlank() } ?: "image/*"
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(sendIntent, "发送表情").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching {
            context.startActivity(chooser)
        }.onFailure {
            Log.e(TAG, "启动分享面板失败", it)
        }
    }

    /** 通过系统分享发送文字。 */
    private fun shareText(context: Context, meme: MemeItem) {
        val text = meme.textContent?.takeIf { it.isNotBlank() } ?: meme.name
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(sendIntent, "发送文字").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching {
            context.startActivity(chooser)
        }.onFailure {
            Log.e(TAG, "启动分享面板失败", it)
        }
    }

    /**
     * 通过无障碍服务发送 meme。
     *
     * 实现：将 meme 完整信息序列化为 JSON 写入 filesDir/pending_send.json，
     * 然后发送广播 [ACTION_SEND_MEME]（限定本应用包名），无障碍服务监听该广播后读取文件执行发送。
     */
    fun sendViaAccessibility(context: Context, meme: MemeItem) {
        val json = meme.toJson()
        val pendingFile = File(context.filesDir, PENDING_SEND_FILE)

        runCatching {
            pendingFile.writeText(json)
        }.onFailure {
            Log.e(TAG, "写入 pending_send.json 失败", it)
            return
        }

        val intent = Intent(ACTION_SEND_MEME).apply {
            setPackage(context.packageName)
            putExtra("id", meme.id)
            putExtra("absPath", meme.absPath)
            putExtra("type", meme.type)
        }
        context.sendBroadcast(intent)
        Log.d(TAG, "已通知无障碍服务发送 meme: ${meme.id}")
    }
}
