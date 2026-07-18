package com.mako.mako_meme.ime

import android.content.Context
import android.graphics.Typeface
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.RecyclerView

/**
 * meme 网格列表适配器（4 列圆角卡片）。
 *
 * - 图片类（absPath 非空）：用 [ImageView] + [BitmapLoader] 异步加载，带内存缓存。
 * - 文字类（absPath 为空）：用 [TextView] 显示 textContent。
 * - 点击触发 [onMemeClick] 回调；长按显示文件名 Toast。
 * - 选中态：卡片外缘加 accent 描边。
 *
 * 配色全部走 [ImeTheme]，圆角 10dp，参考 Material 卡片风格。
 */
class MemeGridAdapter(
    private val context: Context,
    private val theme: ImeTheme,
    private val onMemeClick: (MemeItem) -> Unit,
) : RecyclerView.Adapter<MemeGridAdapter.MemeViewHolder>() {

    companion object {
        const val TYPE_IMAGE = 0
        const val TYPE_TEXT = 1
        private const val CELL_SIZE_DP = 84
        private const val CARD_RADIUS_DP = 10
        private const val SELECT_STROKE_DP = 2
    }

    private val items = mutableListOf<MemeItem>()
    private val cellSizePx: Int = dp(CELL_SIZE_DP)
    private var selectedId: String? = null

    /** 提交新数据并刷新。 */
    fun submit(list: List<MemeItem>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    /** 设置当前选中的 meme id，刷新高亮。 */
    fun setSelected(id: String?) {
        val old = selectedId
        selectedId = id
        if (old != id) {
            notifyDataSetChanged()
        }
    }

    override fun getItemViewType(position: Int): Int {
        return if (items[position].isImage) TYPE_IMAGE else TYPE_TEXT
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MemeViewHolder {
        // 用 FrameLayout 包一层，方便统一控制圆角背景 + 选中态描边
        val card = FrameLayout(context).apply {
            layoutParams = ViewGroup.LayoutParams(cellSizePx, cellSizePx)
        }
        val content: View = if (viewType == TYPE_IMAGE) {
            ImageView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: android.graphics.Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, dp(CARD_RADIUS_DP).toFloat())
                    }
                }
            }
        } else {
            TextView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                gravity = Gravity.CENTER
                setTextColor(theme.text)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setPadding(dp(8), dp(8), dp(8), dp(8))
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
                typeface = Typeface.DEFAULT
            }
        }
        card.addView(content)
        return MemeViewHolder(card)
    }

    override fun onBindViewHolder(holder: MemeViewHolder, position: Int) {
        val item = items[position]
        val card = holder.itemView as FrameLayout
        val isSelected = item.id == selectedId

        // 卡片背景：圆角 + 选中态描边
        card.background = android.graphics.drawable.GradientDrawable().apply {
            color = android.content.res.ColorStateList.valueOf(theme.cardBg)
            cornerRadius = dp(CARD_RADIUS_DP).toFloat()
            if (isSelected) {
                setStroke(dp(SELECT_STROKE_DP), theme.accent)
            }
        }

        if (getItemViewType(position) == TYPE_IMAGE) {
            val iv = card.getChildAt(0) as ImageView
            if (item.absPath.isNotEmpty()) {
                BitmapLoader.load(item.absPath, iv, cellSizePx)
            } else {
                iv.setImageDrawable(null)
            }
        } else {
            val tv = card.getChildAt(0) as TextView
            tv.text = item.textContent?.takeIf { it.isNotBlank() } ?: item.name
        }
    }

    override fun getItemCount(): Int = items.size

    inner class MemeViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        init {
            itemView.setOnClickListener {
                val pos = bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) {
                    itemView.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
                    onMemeClick(items[pos])
                }
            }
            itemView.setOnLongClickListener {
                val pos = bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) {
                    Toast.makeText(context, items[pos].name, Toast.LENGTH_SHORT).show()
                }
                true
            }
        }
    }

    private fun dp(v: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            context.resources.displayMetrics
        ).toInt()
    }
}
