package com.mako.mako_meme.accessibility

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.mako.mako_meme.ime.MemeItem
import java.io.File

/**
 * 微信发送图片自动化适配器。
 *
 * 自动化流程（在聊天界面）：
 * 1. 点击右下角"+"按钮（contentDescription 含"更多功能"或"+"）
 * 2. 在弹出菜单点击"相册"
 * 3. 在相册选择界面，点击第一张图（最新图，即我们复制的临时图）
 * 4. 点击"发送"按钮
 *
 * **需真机校准**：
 * - "+"按钮的 contentDescription 在不同版本可能是"更多功能按钮""加号""切换键盘"等
 * - "相册"入口文本可能是"相册"或图标
 * - 相册网格的第一张图通常是最新的，但取决于微信排序
 * - 发送按钮的 viewId 形如 `com.tencent.mm:id/...`，版本间会变
 *
 * 建议用 `uiautomatorviewer` 截图后更新下面的常量。
 */
class WeChatAdapter : AppAdapter {

    companion object {
        private const val TAG = "WeChatAdapter"
        /** "+"按钮的常见 contentDescription 关键词。 */
        private val PLUS_KEYWORDS = listOf("更多功能", "加号", "+", "切换到菜单")
        /** 相册入口的常见文本。 */
        private val ALBUM_KEYWORDS = listOf("相册", "图片", "照片")
        /** 发送按钮的常见文本。 */
        private val SEND_KEYWORDS = listOf("发送", "确定", "完成")
    }

    override fun send(service: MakoAccessibilityService, meme: MemeItem, imageFile: File) {
        Thread {
            try {
                Log.i(TAG, "微信自动化开始: ${meme.name}")
                // 步骤1：点击"+"按钮
                if (!clickPlusButton(service)) {
                    Log.e(TAG, "未找到\"+\"按钮，请确保在聊天界面")
                    return@Thread
                }
                delay(800)

                // 步骤2：点击"相册"
                if (!clickAlbumEntry(service)) {
                    Log.e(TAG, "未找到相册入口")
                    return@Thread
                }
                delay(1000)

                // 步骤3：选择第一张图（最新）
                if (!selectFirstImage(service)) {
                    Log.e(TAG, "未找到可选图片")
                    return@Thread
                }
                delay(600)

                // 步骤4：点击发送
                if (!clickSendButton(service)) {
                    Log.e(TAG, "未找到发送按钮")
                    return@Thread
                }
                Log.i(TAG, "微信自动化完成")
            } catch (e: Exception) {
                Log.e(TAG, "自动化异常", e)
            }
        }.start()
    }

    /** 点击聊天界面右下角的"+"按钮。 */
    private fun clickPlusButton(service: MakoAccessibilityService): Boolean {
        val root = root(service) ?: return false
        // 优先按 contentDescription 查找
        for (kw in PLUS_KEYWORDS) {
            val node = MakoAccessibilityService.findByDesc(root, kw)
            if (node != null && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                Log.d(TAG, "通过描述点击\"+\": $kw")
                return true
            }
        }
        // 兜底：按文本"+"
        return clickByText(service, "+")
    }

    /** 点击弹出菜单里的"相册"。 */
    private fun clickAlbumEntry(service: MakoAccessibilityService): Boolean {
        for (kw in ALBUM_KEYWORDS) {
            if (clickByText(service, kw)) {
                Log.d(TAG, "点击相册: $kw")
                return true
            }
        }
        return false
    }

    /** 选择相册网格里的第一张图（通常是最新图）。 */
    private fun selectFirstImage(service: MakoAccessibilityService): Boolean {
        val root = root(service) ?: return false
        // 查找所有可点击的 ImageView（相册网格项）
        val images = MakoAccessibilityService.findNodesByClassName(root, "android.widget.ImageView")
        val target = images.firstOrNull { it.isClickable } ?: images.firstOrNull()
        return target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
    }

    /** 点击"发送"按钮。 */
    private fun clickSendButton(service: MakoAccessibilityService): Boolean {
        for (kw in SEND_KEYWORDS) {
            if (clickByText(service, kw)) {
                Log.d(TAG, "点击发送: $kw")
                return true
            }
        }
        return false
    }
}
