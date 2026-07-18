package com.mako.mako_meme.ime

import android.inputmethodservice.InputMethodService
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView

/**
 * Mako 表情包输入法服务。
 *
 * 键盘布局（代码构建，参考 Gboard / Rime 风格）：
 * ```
 * ┌──────────────────────────────────────────────┐
 * │ [🌐] [⌨] [⌫]                  [📤] [♿]      │ ← 图标化操作栏（紧凑、圆角）
 * │ [全部][表情][GIF][图片][文字]...（横向滚动） │ ← pill Tab（圆角胶囊选中态）
 * │ 🔍 搜索表情包...                             │ ← 胶囊搜索框
 * │ ┌──┐ ┌──┐ ┌──┐ ┌──┐                         │
 * │ │  │ │  │ │  │ │  │  ...（4 列圆角卡片）    │
 * │ └──┘ └──┘ └──┘ └──┘                         │
 * └──────────────────────────────────────────────┘
 * ```
 *
 * 设计要点：
 * - 所有按键 8dp 圆角，按 [ImeTheme.keyBg] / [ImeTheme.keyFuncBg] 区分语义
 * - 顶栏改用 [ImageButton]（图标）替代文字按钮，更紧凑、更接近原生输入法
 * - Tab 选中态用 pill 背景圆角胶囊
 * - 网格单元格走 [ImeTheme.cardBg] 配色，圆角 10dp
 * - 按键按下触发 [HapticFeedbackConstants.KEYBOARD_TAP] 触感反馈
 */
class MakoImeService : InputMethodService() {

    companion object {
        /** 键盘高度（dp）。 */
        private const val KEYBOARD_HEIGHT_DP = 280
        /** 网格列数。 */
        private const val GRID_SPAN = 4
        /** 按键圆角半径（dp）。 */
        private const val KEY_RADIUS_DP = 8
        /** Tab 圆角半径（dp）。 */
        private const val TAB_RADIUS_DP = 14
    }

    private lateinit var repository: MemeRepository
    private lateinit var adapter: MemeGridAdapter
    private lateinit var recyclerView: RecyclerView
    private lateinit var theme: ImeTheme

    /** 全部 meme（已加载）。 */
    private val allMemes = mutableListOf<MemeItem>()

    /** 当前选中的分类类型，null 表示"全部"。 */
    private var currentType: String? = null

    /** 当前搜索关键字。 */
    private var currentQuery: String = ""

    /** 当前选中的 meme（用于发送）。 */
    private var selectedMeme: MemeItem? = null

    /** Tab 视图列表，用于高亮切换。 */
    private val tabViews = mutableListOf<TextView>()

    /** QWERTY 键盘模式（用于搜索输入）。 */
    private var qwertyMode = false

    private lateinit var btnShare: ImageButton
    private lateinit var btnAccessibility: ImageButton
    private lateinit var btnKeyboard: ImageButton
    private lateinit var searchInput: TextView
    private lateinit var contentContainer: LinearLayout

    /** 分类定义：显示名 → 类型（null = 全部）。 */
    private val categories = listOf(
        "全部" to null,
        "表情" to MemeItem.TYPE_EMOJI,
        "GIF" to MemeItem.TYPE_GIF,
        "图片" to MemeItem.TYPE_IMAGE,
        "文字" to MemeItem.TYPE_TEXT,
        "角色卡" to MemeItem.TYPE_CHARACTER_CARD,
        "立绘" to MemeItem.TYPE_PORTRAIT,
        "CG" to MemeItem.TYPE_CG
    )

    /** QWERTY 键盘布局定义。 */
    private val qwertyRows = listOf(
        "qwertyuiop".toList(),
        "asdfghjkl".toList(),
        "zxcvbnm".toList()
    )

    override fun onCreate() {
        super.onCreate()
        repository = MemeRepository(this)
    }

    override fun onCreateInputView(): View {
        // 加载主应用同步的主题配色
        theme = ImeTheme.load(this)
        adapter = MemeGridAdapter(this, theme) { meme -> onMemeClicked(meme) }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(KEYBOARD_HEIGHT_DP)
            )
            setBackgroundColor(theme.bg)
        }

        root.addView(buildActionBar())
        root.addView(buildDivider())
        root.addView(buildCategoryTabs())
        root.addView(buildSearchBar())
        root.addView(buildDivider())

        // 内容容器：meme 网格 / QWERTY 键盘切换
        contentContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        contentContainer.addView(buildGrid())
        root.addView(contentContainer)

        // 首次加载 meme 数据
        loadMemes()

        return root
    }

    /** 第一行：图标化操作栏（切换 / 键盘 / 退格 / 分享 / 无障碍）。 */
    private fun buildActionBar(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(40)
            )
            setPadding(dp(8), dp(4), dp(8), dp(4))
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(theme.surface)

            // 左侧：切换输入法 + 键盘
            addView(iconButton(android.R.drawable.ic_menu_sort_by_size, "切换输入法") {
                val switched = switchToPreviousInputMethod()
                if (!switched) {
                    Toast.makeText(this@MakoImeService, "没有上一个输入法", Toast.LENGTH_SHORT).show()
                }
            })
            addView(spacer(dp(4)))
            btnKeyboard = iconButton(android.R.drawable.ic_menu_edit, "切换键盘") {
                toggleQwerty()
            }
            addView(btnKeyboard)
            addView(spacer(dp(4)))
            // 退格（仅在 QWERTY 模式可见，逻辑上保留位）
            addView(iconButton(android.R.drawable.ic_input_delete, "退格") {
                if (currentQuery.isNotEmpty()) {
                    currentQuery = currentQuery.dropLast(1)
                    searchInput.text = currentQuery
                    applyFilter()
                }
            })

            // 中间撑开
            addView(View(this@MakoImeService).apply {
                layoutParams = LinearLayout.LayoutParams(0, dp(1), 1f)
            })

            // 右侧：分享 + 无障碍发送
            btnShare = iconButton(android.R.drawable.ic_menu_share, "分享发送") {
                val meme = selectedMeme
                if (meme != null) {
                    MemeSender.sendViaShare(this@MakoImeService, meme)
                } else {
                    Toast.makeText(this@MakoImeService, "请先选择一个表情", Toast.LENGTH_SHORT).show()
                }
            }.apply { alpha = 0.4f; isEnabled = false }
            addView(btnShare)
            addView(spacer(dp(4)))
            btnAccessibility = iconButton(android.R.drawable.ic_menu_help, "无障碍发送") {
                val meme = selectedMeme
                if (meme != null) {
                    MemeSender.sendViaAccessibility(this@MakoImeService, meme)
                } else {
                    Toast.makeText(this@MakoImeService, "请先选择一个表情", Toast.LENGTH_SHORT).show()
                }
            }.apply { alpha = 0.4f; isEnabled = false }
            addView(btnAccessibility)
        }
    }

    /** 创建图标按钮：圆角、按下触感反馈、统一尺寸。 */
    private fun iconButton(iconRes: Int, desc: String, onClick: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(iconRes)
            contentDescription = desc
            // 圆角背景：GradientDrawable 替代默认 Button 直角背景
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            imageTintList = android.content.res.ColorStateList.valueOf(theme.text)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(30)).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
    }

    /** 间隔视图。 */
    private fun spacer(width: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(width, 1)
        }
    }

    /** 1dp 高度的分割线。 */
    private fun buildDivider(): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(1)
            )
            setBackgroundColor(theme.divider)
        }
    }

    /** 第二行：分类 Tab（横向可滚动，pill 选中态）。 */
    private fun buildCategoryTabs(): View {
        tabViews.clear()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
        }
        categories.forEachIndexed { idx, (label, type) ->
            val tab = TextView(this).apply {
                text = label
                textSize = 13f
                setPadding(dp(14), dp(6), dp(14), dp(6))
                setTextColor(theme.subText)
                typeface = Typeface.DEFAULT
                isClickable = true
                background = android.graphics.drawable.GradientDrawable().apply {
                    color = android.content.res.ColorStateList.valueOf(0x00000000)
                    cornerRadius = dp(TAB_RADIUS_DP).toFloat()
                }
                setOnClickListener {
                    currentType = type
                    updateTabHighlight(this)
                    applyFilter()
                }
            }
            tabViews.add(tab)
            row.addView(tab)
            // Tab 间留 6dp 间隔
            if (idx < categories.size - 1) {
                row.addView(spacer(dp(6)))
            }
        }
        // 默认高亮"全部"
        updateTabHighlight(tabViews.first())

        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(44)
            )
            setBackgroundColor(theme.bg)
        }
    }

    /** 第三行：搜索框（胶囊形，点击切换到 QWERTY）。 */
    private fun buildSearchBar(): View {
        searchInput = TextView(this).apply {
            text = currentQuery
            hint = "搜索表情包名称 / 标签..."
            textSize = 13f
            setSingleLine(true)
            setTextColor(theme.text)
            setHintTextColor(theme.subText)
            setPadding(dp(14), dp(8), dp(14), dp(8))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.surface)
                cornerRadius = dp(16).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(36)
            ).apply {
                setMargins(dp(8), dp(2), dp(8), dp(4))
            }
            isClickable = true
            setOnClickListener {
                if (!qwertyMode) toggleQwerty()
            }
            // 搜索框前置放大镜图标（用 compound drawable）
            setCompoundDrawablesWithIntrinsicBounds(
                android.R.drawable.ic_menu_search, 0, 0, 0
            )
            compoundDrawablePadding = dp(8)
        }
        return searchInput
    }

    /** 网格区域。 */
    private fun buildGrid(): View {
        recyclerView = RecyclerView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            layoutManager = GridLayoutManager(this@MakoImeService, GRID_SPAN)
            adapter = this@MakoImeService.adapter
            setPadding(dp(6), dp(4), dp(6), dp(4))
            setBackgroundColor(theme.bg)
            // 网格项间距通过 ItemDecoration 控制
            addItemDecoration(GridSpacingItemDecoration(GRID_SPAN, dp(6), false))
        }
        return recyclerView
    }

    /** QWERTY 键盘视图：圆角按键，参考 Gboard 风格。 */
    private fun buildQwertyKeyboard(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(dp(6), dp(6), dp(6), dp(6))
            setBackgroundColor(theme.bg)
            gravity = Gravity.CENTER_HORIZONTAL
        }
        qwertyRows.forEach { row ->
            val rowView = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    0,
                    1f
                )
            }
            row.forEach { ch ->
                rowView.addView(qwertyKey(ch.toString(), 1f) {
                    currentQuery += ch.toString()
                    searchInput.text = currentQuery
                    applyFilter()
                })
            }
            root.addView(rowView)
        }
        // 最后一行：退格 + 空格 + 完成
        val lastRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        lastRow.addView(funcKey("⌫", 1.5f) {
            if (currentQuery.isNotEmpty()) {
                currentQuery = currentQuery.dropLast(1)
                searchInput.text = currentQuery
                applyFilter()
            }
        })
        lastRow.addView(funcKey("空格", 4f) {
            currentQuery += " "
            searchInput.text = currentQuery
            applyFilter()
        })
        lastRow.addView(accentKey("完成", 1.5f) {
            // 切回表情网格查看搜索结果
            if (qwertyMode) toggleQwerty()
        })
        root.addView(lastRow)
        return root
    }

    /** QWERTY 字母键：圆角、keyBg 背景。 */
    private fun qwertyKey(label: String, weight: Float, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(theme.text)
            typeface = Typeface.DEFAULT
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(3), dp(3), dp(3), dp(3))
            layoutParams = lp
            isClickable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
    }

    /** QWERTY 功能键：圆角、keyFuncBg 背景（与字母键视觉区分）。 */
    private fun funcKey(label: String, weight: Float, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(theme.subText)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(3), dp(3), dp(3), dp(3))
            layoutParams = lp
            isClickable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
    }

    /** QWERTY 强调键（如"完成"）：accent 背景。 */
    private fun accentKey(label: String, weight: Float, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(theme.onAccent)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.accent)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(3), dp(3), dp(3), dp(3))
            layoutParams = lp
            isClickable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
    }

    /** 切换 QWERTY 键盘 / 表情网格。 */
    private fun toggleQwerty() {
        qwertyMode = !qwertyMode
        contentContainer.removeAllViews()
        if (qwertyMode) {
            contentContainer.addView(buildQwertyKeyboard())
            btnKeyboard.background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.accent)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            btnKeyboard.imageTintList = android.content.res.ColorStateList.valueOf(theme.onAccent)
        } else {
            contentContainer.addView(recyclerView)
            btnKeyboard.background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            btnKeyboard.imageTintList = android.content.res.ColorStateList.valueOf(theme.text)
        }
    }

    /** 点击 meme 条目：选中并提示。 */
    private fun onMemeClicked(meme: MemeItem) {
        selectedMeme = meme
        btnShare.isEnabled = true
        btnAccessibility.isEnabled = true
        btnShare.alpha = 1f
        btnAccessibility.alpha = 1f
        adapter.setSelected(meme.id)
        Toast.makeText(this, "已选中: ${meme.name}", Toast.LENGTH_SHORT).show()
    }

    /** 高亮当前选中的 Tab：选中态用 pill 背景。 */
    private fun updateTabHighlight(selected: TextView) {
        tabViews.forEach { tab ->
            val isSelected = tab === selected
            tab.background = android.graphics.drawable.GradientDrawable().apply {
                if (isSelected) {
                    color = android.content.res.ColorStateList.valueOf(theme.tabBg)
                } else {
                    color = android.content.res.ColorStateList.valueOf(0x00000000)
                }
                cornerRadius = dp(TAB_RADIUS_DP).toFloat()
            }
            if (isSelected) {
                tab.setTextColor(theme.tabText)
                tab.typeface = Typeface.DEFAULT_BOLD
            } else {
                tab.setTextColor(theme.subText)
                tab.typeface = Typeface.DEFAULT
            }
        }
    }

    /** 异步加载 meme 数据并刷新列表。 */
    private fun loadMemes() {
        repository.loadMemes { list ->
            allMemes.clear()
            allMemes.addAll(list)
            applyFilter()
        }
    }

    /** 按当前分类 + 搜索关键字过滤并刷新网格。 */
    private fun applyFilter() {
        var filtered: List<MemeItem> = allMemes
        // 按分类过滤
        if (currentType != null) {
            filtered = filtered.filter { it.type == currentType }
        }
        // 按搜索关键字过滤
        filtered = repository.search(currentQuery, filtered)
        adapter.submit(filtered)
    }

    override fun onDestroy() {
        super.onDestroy()
        repository.release()
    }

    private fun dp(v: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
}
