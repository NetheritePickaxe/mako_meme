package com.mako.mako_meme.ime

import org.json.JSONArray
import org.json.JSONObject

/**
 * meme 数据模型，对应 ContentProvider 返回的 JSON 结构。
 *
 * 字段与 Flutter 侧 [MemeIndexExporter] 导出的索引一致：
 * id / name / type / absPath / tags / folderId / isFavorite / mimeType / textContent
 *
 * type 取值：emoji / gif / image / text / portrait / cg / character_card
 */
data class MemeItem(
    val id: String,
    val name: String,
    val type: String,
    val absPath: String,
    val tags: List<String>,
    val folderId: String?,
    val isFavorite: Boolean,
    val mimeType: String,
    val textContent: String?
) {
    /** 是否为图片类（有绝对路径可加载）。文字类 absPath 为空。 */
    val isImage: Boolean get() = absPath.isNotEmpty()

    /** 序列化为 JSON 字符串，用于写入 pending_send.json 通知无障碍服务。 */
    fun toJson(): String {
        val obj = JSONObject()
        obj.put("id", id)
        obj.put("name", name)
        obj.put("type", type)
        obj.put("absPath", absPath)
        val tagsArr = JSONArray()
        tags.forEach { tagsArr.put(it) }
        obj.put("tags", tagsArr)
        obj.put("folderId", folderId ?: JSONObject.NULL)
        obj.put("isFavorite", isFavorite)
        obj.put("mimeType", mimeType)
        obj.put("textContent", textContent ?: JSONObject.NULL)
        return obj.toString()
    }

    companion object {
        /** 类型常量，与 Flutter 侧 [Meme.typeXxx] 保持一致。 */
        const val TYPE_EMOJI = "emoji"
        const val TYPE_GIF = "gif"
        const val TYPE_IMAGE = "image"
        const val TYPE_TEXT = "text"
        const val TYPE_PORTRAIT = "portrait"
        const val TYPE_CG = "cg"
        const val TYPE_CHARACTER_CARD = "character_card"

        /**
         * 解析 ContentProvider 返回的 JSON 数组字符串为 [List<MemeItem>]。
         * 容错：任意一条解析失败会被跳过；整体解析失败返回空列表。
         */
        fun fromJson(json: String): List<MemeItem> {
            if (json.isBlank()) return emptyList()
            return try {
                val arr = JSONArray(json)
                buildList {
                    for (i in 0 until arr.length()) {
                        val obj = arr.optJSONObject(i) ?: continue
                        val item = runCatching { fromJsonObject(obj) }.getOrNull()
                        if (item != null) add(item)
                    }
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        private fun fromJsonObject(obj: JSONObject): MemeItem {
            val tags = mutableListOf<String>()
            obj.optJSONArray("tags")?.let { arr ->
                for (i in 0 until arr.length()) {
                    tags.add(arr.optString(i))
                }
            }
            return MemeItem(
                id = obj.optString("id"),
                name = obj.optString("name"),
                type = obj.optString("type", TYPE_IMAGE),
                absPath = obj.optString("absPath", ""),
                tags = tags,
                folderId = optNullableString(obj, "folderId"),
                isFavorite = obj.optBoolean("isFavorite", false),
                mimeType = obj.optString("mimeType", ""),
                textContent = optNullableString(obj, "textContent")
            )
        }

        /** 读取可能为 null 的字符串字段，null 时返回 null。 */
        private fun optNullableString(obj: JSONObject, key: String): String? =
            if (obj.has(key) && !obj.isNull(key)) obj.optString(key) else null
    }
}
