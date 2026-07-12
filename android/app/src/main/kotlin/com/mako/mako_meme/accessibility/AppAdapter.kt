package com.mako.mako_meme.accessibility

import android.view.accessibility.AccessibilityNodeInfo
import com.mako.mako_meme.ime.MemeItem
import java.io.File

/**
 * App 自动化适配器接口。
 *
 * 每个目标 App（微信/QQ）实现此接口，描述"在聊天界面发送一张图片"的自动化步骤。
 *
 * **注意**：下面的查找规则基于公开已知的 UI 信息，控件 ID / 文本可能随 App 版本变化。
 * 实际使用前需在真机上用 `uiautomatorviewer` 校准并更新 [WeChatAdapter] / [QQAdapter]。
 */
interface AppAdapter {

    /**
     * 在当前聊天界面执行发送 [meme]（图片已复制到 [imageFile]）的自动化流程。
     * 实现应在异步线程或带延迟执行，避免阻塞无障碍主线程。
     */
    fun send(
        service: MakoAccessibilityService,
        meme: MemeItem,
        imageFile: File
    )

    /** 获取 root 节点（封装空判断）。 */
    fun root(service: MakoAccessibilityService): AccessibilityNodeInfo? =
        service.rootInActiveWindow

    /** 点击指定文本的节点，返回是否成功。 */
    fun clickByText(service: MakoAccessibilityService, text: String): Boolean {
        val root = root(service) ?: return false
        val node = MakoAccessibilityService.findByText(root, text) ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    /** 点击指定 viewId 的节点，返回是否成功。 */
    fun clickById(service: MakoAccessibilityService, id: String): Boolean {
        val root = root(service) ?: return false
        val node = MakoAccessibilityService.findById(root, id) ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    /** 点击指定描述的节点，返回是否成功。 */
    fun clickByDesc(service: MakoAccessibilityService, desc: String): Boolean {
        val root = root(service) ?: return false
        val node = MakoAccessibilityService.findByDesc(root, desc) ?: return false
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    /** 延迟执行（毫秒），让 UI 有时间响应。 */
    fun delay(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (_: InterruptedException) {}
    }
}
