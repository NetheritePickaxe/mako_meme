package com.mako.mako_meme.ime

import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.RecyclerView

/**
 * meme 网格列表适配器（4 列）。
 *
 * - 图片类（absPath 非空）：用 [ImageView] + [BitmapLoader] 异步加载，带内存缓存。
 * - 文字类（absPath 为空）：用 [TextView] 显示 textContent。
 * - 点击触发 [onMemeClick] 回调；长按显示文件名 Toast。
 */
class MemeGridAdapter(
    private val context: Context,
    private val onMemeClick: (MemeItem) -> Unit
) : RecyclerView.Adapter<MemeGridAdapter.MemeViewHolder>() {

    companion object {
        const val TYPE_IMAGE = 0
        const val TYPE_TEXT = 1
        private const val CELL_SIZE_DP = 88
    }

    private val items = mutableListOf<MemeItem>()
    private val cellSizePx: Int = dp(CELL_SIZE_DP)

    /** 提交新数据并刷新。 */
    fun submit(list: List<MemeItem>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    override fun getItemViewType(position: Int): Int {
        return if (items[position].isImage) TYPE_IMAGE else TYPE_TEXT
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MemeViewHolder {
        val view: View = if (viewType == TYPE_IMAGE) {
            ImageView(context).apply {
                layoutParams = ViewGroup.LayoutParams(cellSizePx, cellSizePx)
                scaleType = ImageView.ScaleType.CENTER_CROP
                setBackgroundColor(Color.parseColor("#2A2A2A"))
            }
        } else {
            TextView(context).apply {
                layoutParams = ViewGroup.LayoutParams(cellSizePx, cellSizePx)
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setPadding(dp(8), dp(8), dp(8), dp(8))
                setBackgroundColor(Color.parseColor("#3A3A3A"))
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
            }
        }
        return MemeViewHolder(view)
    }

    override fun onBindViewHolder(holder: MemeViewHolder, position: Int) {
        val item = items[position]
        if (getItemViewType(position) == TYPE_IMAGE) {
            val iv = holder.itemView as ImageView
            if (item.absPath.isNotEmpty()) {
                BitmapLoader.load(item.absPath, iv, cellSizePx)
            } else {
                iv.setImageDrawable(null)
            }
        } else {
            val tv = holder.itemView as TextView
            tv.text = item.textContent?.takeIf { it.isNotBlank() } ?: item.name
        }
    }

    override fun getItemCount(): Int = items.size

    inner class MemeViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        init {
            itemView.setOnClickListener {
                val pos = bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) {
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
