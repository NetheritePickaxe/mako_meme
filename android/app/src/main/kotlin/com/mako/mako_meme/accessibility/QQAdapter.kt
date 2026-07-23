package com.mako.mako_meme.accessibility

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.mako.mako_meme.ime.MemeItem
import java.io.File

/**
 * QQ 发送图片自动化适配器。
 *
 * 自动化流程（在聊天界面）：
 * 1. 点击输入框左侧的"图片"图标（contentDescription 含"图片"或"发送图片"）
 * 2. 进入图片选择界面，点击第一张图（最新）
 * 3. 点击"发送"按钮
 *
 * **需真机校准**：QQ 不同版本（手Q / TIM）UI 差异较大，控件文本/ID 需用
 * `uiautomatorviewer` 校准。
 */
class QQAdapter : AppAdapter {

    companion object {
        private const val TAG = "QQAdapter"
        private val IMAGE_ICON_KEYWORDS = listOf("图片", "发送图片", "相册")
        private val SEND_KEYWORDS = listOf("发送", "确定", "完成")
    }

    override fun send(service: MakoAccessibilityService, meme: MemeItem, imageFile: File): Boolean {
        return try {
            Log.i(TAG, "QQ 自动化开始: ${meme.name}")
            // 步骤1：点击图片入口
            if (!clickImageEntry(service)) {
                Log.e(TAG, "未找到图片入口")
                return false
            }
            delay(1000)

            // 步骤2：选择第一张图
            if (!selectFirstImage(service)) {
                Log.e(TAG, "未找到可选图片")
                return false
            }
            delay(600)

            // 步骤3：点击发送
            if (!clickSendButton(service)) {
                Log.e(TAG, "未找到发送按钮")
                return false
            }
            Log.i(TAG, "QQ 自动化完成")
            true
        } catch (e: Exception) {
            Log.e(TAG, "自动化异常", e)
            false
        }
    }

    private fun clickImageEntry(service: MakoAccessibilityService): Boolean {
        val root = root(service) ?: return false
        for (kw in IMAGE_ICON_KEYWORDS) {
            val node = MakoAccessibilityService.findByDesc(root, kw)
            if (node != null && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                Log.d(TAG, "点击图片入口: $kw")
                return true
            }
        }
        // 兜底：按文本
        for (kw in IMAGE_ICON_KEYWORDS) {
            if (clickByText(service, kw)) return true
        }
        return false
    }

    private fun selectFirstImage(service: MakoAccessibilityService): Boolean {
        val root = root(service) ?: return false
        val images = MakoAccessibilityService.findNodesByClassName(root, "android.widget.ImageView")
        val target = images.firstOrNull { it.isClickable } ?: images.firstOrNull()
        return target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
    }

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
