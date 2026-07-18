package com.mako.mako_meme.ime

import android.graphics.Rect
import android.view.View
import androidx.recyclerview.widget.RecyclerView

/**
 * RecyclerView 网格间距装饰：为每个单元格四周添加等距间隔，
 * 可选首行/末行/首列/末列不补 padding（用于配合 RecyclerView 自身的 padding）。
 *
 * @param spanCount 列数
 * @param spacing   单元格间距（px）
 * @param includeEdge 是否在网格外缘也补 spacing
 */
class GridSpacingItemDecoration(
    private val spanCount: Int,
    private val spacing: Int,
    private val includeEdge: Boolean,
) : RecyclerView.ItemDecoration() {

    override fun getItemOffsets(
        outRect: Rect,
        view: View,
        parent: RecyclerView,
        state: RecyclerView.State,
    ) {
        val position = parent.getChildAdapterPosition(view)
        if (position == RecyclerView.NO_POSITION) return
        val column = position % spanCount

        if (includeEdge) {
            // 外缘也补 spacing
            outRect.left = spacing - column * spacing / spanCount
            outRect.right = (column + 1) * spacing / spanCount
            if (position < spanCount) {
                outRect.top = spacing
            }
            outRect.bottom = spacing
        } else {
            // 仅在单元格之间补 spacing，外缘靠 RecyclerView padding
            outRect.left = column * spacing / spanCount
            outRect.right = spacing - (column + 1) * spacing / spanCount
            if (position >= spanCount) {
                outRect.top = spacing
            }
        }
    }
}
