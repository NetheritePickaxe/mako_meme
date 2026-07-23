package com.mako.mako_meme.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.mako.mako_meme.ime.MemeItem
import com.mako.mako_meme.ime.MemeSender
import java.io.File

/**
 * 无障碍服务：接收 IME 的发送指令，在当前前台 App（微信/QQ）中自动化发送表情包。
 *
 * 工作流：
 * 1. IME 调用 [MemeSender.sendViaAccessibility] → 写 pending_send.json + 发广播
 * 2. 本服务 [SendReceiver] 收到广播 → 读取 pending meme
 * 3. 把图片复制到 `Pictures/mako_meme_temp/` 并触发媒体扫描（让相册能看到）
 * 4. 识别当前前台 App，用对应 [AppAdapter] 执行自动化流程
 *
 * **重要**：微信/QQ 的 UI 控件 ID 和文本会随版本变化，[WeChatAdapter] / [QQAdapter]
 * 里的查找规则需要在真机上用 `uiautomatorviewer` 校准。框架已就绪，适配规则待真机调试。
 */
class MakoAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "MakoA11y"
        private const val TEMP_DIR = "mako_meme_temp"

        /** 按文本查找可点击节点。 */
        fun findByText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
            val nodes = root.findAccessibilityNodeInfosByText(text)
            return nodes.firstOrNull { it.isClickable } ?: nodes.firstOrNull()
        }

        /** 按 viewId 查找节点（如 com.tencent.mm:id/xxx）。 */
        fun findById(root: AccessibilityNodeInfo, id: String): AccessibilityNodeInfo? {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            return nodes.firstOrNull()
        }

        /** 按类名递归查找节点。 */
        fun findNodesByClassName(
            root: AccessibilityNodeInfo,
            className: String
        ): List<AccessibilityNodeInfo> {
            val result = mutableListOf<AccessibilityNodeInfo>()
            fun walk(node: AccessibilityNodeInfo) {
                if (node.className?.toString() == className) result.add(node)
                for (i in 0 until node.childCount) {
                    node.getChild(i)?.let(::walk)
                }
            }
            walk(root)
            return result
        }

        /** 按描述（contentDescription）查找节点。 */
        fun findByDesc(root: AccessibilityNodeInfo, desc: String): AccessibilityNodeInfo? {
            fun walk(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
                if (node.contentDescription?.toString()?.contains(desc) == true) return node
                for (i in 0 until node.childCount) {
                    node.getChild(i)?.let { walk(it)?.let { return it } }
                }
                return null
            }
            return walk(root)
        }
    }

    private var sendReceiver: SendReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        sendReceiver = SendReceiver(this)
        val filter = IntentFilter(MemeSender.ACTION_SEND_MEME)
        registerReceiver(sendReceiver, filter, RECEIVER_NOT_EXPORTED)
        Log.i(TAG, "无障碍服务已连接，等待发送指令")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 事件仅用于感知窗口变化，实际发送由广播触发
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        runCatching { unregisterReceiver(sendReceiver) }
        sendReceiver = null
    }

    /**
     * 执行发送流程。
     * @param meme 要发送的表情包
     */
    private fun performSend(meme: MemeItem) {
        Log.i(TAG, "开始发送: ${meme.name} (type=${meme.type})")

        // 文字类：直接 commit 文本到当前输入框
        if (meme.type == MemeItem.TYPE_TEXT || meme.type == MemeItem.TYPE_EMOJI) {
            val text = meme.textContent?.takeIf { it.isNotBlank() } ?: meme.name
            commitText(text)
            return
        }

        // 图片类：复制到公共目录 → 媒体扫描 → 适配器自动化
        if (meme.isImage) {
            val tempFile = copyToPublicPicture(meme) ?: run {
                Log.e(TAG, "复制图片到公共目录失败")
                return
            }
            scanMediaFile(tempFile) {
                executeAppAdapter(meme, tempFile)
            }
        } else {
            Log.w(TAG, "不支持的 meme 类型: ${meme.type}")
        }
    }

    /** 把图片复制到 Pictures/mako_meme_temp/，让相册能扫描到。 */
    private fun copyToPublicPicture(meme: MemeItem): File? {
        val src = File(meme.absPath)
        if (!src.exists()) {
            Log.e(TAG, "源图片不存在: ${meme.absPath}")
            return null
        }
        val dir = File(Environment.getExternalStorageDirectory(), "Pictures/$TEMP_DIR")
        if (!dir.exists()) dir.mkdirs()
        val dest = File(dir, "${meme.id}_${src.name}")
        return runCatching {
            src.copyTo(dest, overwrite = true)
            Log.d(TAG, "已复制到: ${dest.absolutePath}")
            dest
        }.getOrElse {
            Log.e(TAG, "复制失败", it)
            null
        }
    }

    /** 触发媒体扫描，让相册立即看到新图片。 */
    private fun scanMediaFile(file: File, onDone: () -> Unit) {
        MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf("image/*")
        ) { _, _ -> onDone() }
    }

    /** 识别当前前台 App 并执行对应适配器。失败时自动降级到系统分享。 */
    private fun executeAppAdapter(meme: MemeItem, imageFile: File) {
        val pkg = currentPackage() ?: ""
        Log.d(TAG, "当前前台包名: $pkg")
        val adapter: AppAdapter = when {
            pkg.contains("com.tencent.mm") -> WeChatAdapter()
            pkg.contains("com.tencent.mobileqq") || pkg.contains("com.tencent.tim") -> QQAdapter()
            else -> {
                Log.w(TAG, "当前 App ($pkg) 暂不支持无障碍自动发送，回退到系统分享")
                MemeSender.sendViaShare(this, meme)
                return
            }
        }
        val success = runCatching {
            adapter.send(this, meme, imageFile)
        }.getOrDefault(false)
        if (!success) {
            Log.w(TAG, "无障碍发送失败，回退到系统分享")
            MemeSender.sendViaShare(this, meme)
        }
    }

    /** 获取当前前台 App 包名。 */
    private fun currentPackage(): String? {
        val info = rootInActiveWindow ?: return null
        return info.packageName?.toString()
    }

    /** 提交文本到当前聚焦的输入框。 */
    private fun commitText(text: String) {
        val root = rootInActiveWindow ?: return
        val editTexts = findNodesByClassName(root, "android.widget.EditText")
        val target = editTexts.firstOrNull { it.isFocused } ?: editTexts.firstOrNull()
        target?.let {
            val args = android.os.Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            it.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            Log.d(TAG, "已提交文本: $text")
        } ?: Log.w(TAG, "未找到可输入的 EditText")
    }

    // ===== 广播接收器 =====

    private class SendReceiver(val service: MakoAccessibilityService) : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != MemeSender.ACTION_SEND_MEME) return
            val meme = readPendingMeme(context) ?: return
            service.performSend(meme)
        }

        private fun readPendingMeme(context: Context): MemeItem? {
            val file = File(context.filesDir, "pending_send.json")
            if (!file.exists()) return null
            return runCatching {
                MemeItem.fromJson(file.readText()).firstOrNull()
            }.getOrElse {
                Log.e(TAG, "读取 pending_send.json 失败", it)
                null
            }
        }
    }
}
