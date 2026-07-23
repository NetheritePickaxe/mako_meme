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
        /** 网格列数。3 列以显示更大缩略图。 */
        private const val GRID_SPAN = 3
        /** 按键圆角半径（dp）。 */
        private const val KEY_RADIUS_DP = 8
        /** Tab 圆角半径（dp）。 */
        private const val TAB_RADIUS_DP = 14
        /** QWERTY 字母键文字大小。 */
        private const val QWERTY_TEXT_SIZE = 20f
        /** QWERTY 功能键文字大小。 */
        private const val FUNC_TEXT_SIZE = 15f
        /** QWERTY 行间距/键间距（dp）。 */
        private const val QWERTY_GAP_DP = 4
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

    /** Shift 大写锁定状态。 */
    private var shiftEnabled = false

    /** Tab 视图列表，用于高亮切换。 */
    private val tabViews = mutableListOf<TextView>()

    /** QWERTY 键盘模式（用于搜索输入）。 */
    private var qwertyMode = false

    private lateinit var btnShare: ImageButton
    private lateinit var btnAccessibility: ImageButton
    private lateinit var btnFavorite: ImageButton
    private lateinit var btnKeyboard: ImageButton
    private lateinit var searchInput: TextView
    private lateinit var contentContainer: LinearLayout

    /** 从 meme 数据动态构建的分类列表（"全部" + 存在的类型）。首次加载后重建。 */
    private val dynamicCategories: MutableList<Pair<String, String?>> = mutableListOf("全部" to null)

    /** 类型中文标签映射。 */
    private val typeLabels = mapOf(
        MemeItem.TYPE_EMOJI to "表情",
        MemeItem.TYPE_GIF to "GIF",
        MemeItem.TYPE_IMAGE to "图片",
        MemeItem.TYPE_TEXT to "文字",
        MemeItem.TYPE_CHARACTER_CARD to "角色卡",
        MemeItem.TYPE_PORTRAIT to "立绘",
        MemeItem.TYPE_CG to "CG",
    )

    /** 根据已有 meme 数据刷新分类列表。 */
    private fun rebuildCategories() {
        val typesInData = allMemes.map { it.type }.distinct().sorted()
        dynamicCategories.clear()
        dynamicCategories.add("全部" to null)
        for (t in typesInData) {
            val label = typeLabels[t] ?: t
            dynamicCategories.add(label to t)
        }
        // 重建 tab 视图
        val tabRow = tabContainer.getChildAt(0) as? LinearLayout ?: return
        tabRow.removeAllViews()
        tabViews.clear()
        buildCategoryTabsInto(tabRow)
        // 重置到"全部"
        currentType = null
        if (tabViews.isNotEmpty()) {
            updateTabHighlight(tabViews.first())
        }
    }

    private lateinit var tabContainer: HorizontalScrollView

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

        // 动态键盘高度：屏幕高度的 60%，最大 600dp
        val displayMetrics = resources.displayMetrics
        val keyboardHeightPx = minOf(
            (displayMetrics.heightPixels * 0.6f).toInt(),
            dp(600)
        )

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                keyboardHeightPx
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

            // 右侧：收藏 + 分享 + 无障碍发送
            btnFavorite = iconButton(android.R.drawable.ic_menu_myplaces, "收藏") {
                val meme = selectedMeme ?: return@iconButton
                // 通过广播通知主应用切换收藏状态（仅显示提示）
                Toast.makeText(this@MakoImeService,
                    if (meme.isFavorite) "已取消收藏: ${meme.name}" else "已收藏: ${meme.name}",
                    Toast.LENGTH_SHORT).show()
            }.apply { alpha = 0.4f; isEnabled = false }
            addView(btnFavorite)
            addView(spacer(dp(4)))
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
        buildCategoryTabsInto(row)
        updateTabHighlight(tabViews.first())

        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(44)
            )
            setBackgroundColor(theme.bg)
        }.also { tabContainer = it }
    }

    /** 将分类标签填充到已有 [row] 中（用于首次构建或重建）。 */
    private fun buildCategoryTabsInto(row: LinearLayout) {
        dynamicCategories.forEachIndexed { idx, (label, type) ->
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
            if (idx < dynamicCategories.size - 1) {
                row.addView(spacer(dp(6)))
            }
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

    /**
     * QWERTY 键盘视图：圆角按键，参考系统输入法 / Rime 布局。
     *
     * 布局：
     * ```
     *  q w e r t y u i o p
     *   a s d f g h j k l
     *  ⇧ z x c v b n m  ⌫     ← 删除键在右下角"完成"上方
     *  [表情]   空格    [完成]  ← 完成键在右下角
     * ```
     *
     * 设计要点：
     * - 字母键 1f 等宽，行 2/3 通过左右留白居中，视觉对齐
     * - 删除键固定在第三行右侧，紧贴"完成"键上方
     * - 字母键 textSize 20f，比之前 16f 大幅增加，便于点击
     * - 键间距 4dp，按键整体变大
     */
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
        // 第 1 行：q w e r t y u i o p（10 键）
        root.addView(buildQwertyRow(qwertyRows[0], shiftEnabled))
        // 第 2 行：a s d f g h j k l（9 键，居中显示，左右留白）
        root.addView(buildQwertyRow(qwertyRows[1], shiftEnabled, leftPadding = 0.5f, rightPadding = 0.5f))
        // 第 3 行：⇧ z x c v b n m ⌫（左侧 shift 占位 + 7 字母 + 右侧删除键）
        // 删除键位于右下角"完成"键的正上方
        val row3 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        // Shift 键：切换大小写模式
        row3.addView(shiftKey(1.5f))
        qwertyRows[2].forEach { ch ->
            val display = if (shiftEnabled) ch.uppercaseChar() else ch
            val typed = if (shiftEnabled) ch.uppercaseChar() else ch
            row3.addView(qwertyKey(display.toString(), 1f) {
                currentQuery += typed.toString()
                searchInput.text = currentQuery
                applyFilter()
            })
        }
        // 右侧删除键（与下方"完成"键宽度一致，垂直对齐）
        row3.addView(funcKey("⌫", 1.5f) {
            if (currentQuery.isNotEmpty()) {
                currentQuery = currentQuery.dropLast(1)
                searchInput.text = currentQuery
                applyFilter()
            }
        })
        root.addView(row3)
        // 第 4 行：[表情切换] + 空格 + [完成] —— 删除键的下方就是"完成"
        val lastRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        // 表情切换键（与左侧 shift 等宽，视觉对称）
        lastRow.addView(funcKey("😀", 1.5f) {
            // 切回表情网格查看搜索结果
            if (qwertyMode) toggleQwerty()
        })
        lastRow.addView(funcKey("空格", 5f) {
            currentQuery += " "
            searchInput.text = currentQuery
            applyFilter()
        })
        // 完成键：右下角，与上方删除键垂直对齐
        lastRow.addView(accentKey("完成", 1.5f) {
            // 切回表情网格查看搜索结果
            if (qwertyMode) toggleQwerty()
        })
        root.addView(lastRow)
        return root
    }

    /**
     * 构造一行 QWERTY 字母键。
     * [leftPadding]/[rightPadding] 用于让短行（如 a-l 9 键）居中显示。
     */
    private fun buildQwertyRow(
        chars: List<Char>,
        shifted: Boolean = false,
        leftPadding: Float = 0f,
        rightPadding: Float = 0f
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        if (leftPadding > 0f) {
            row.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, 1, leftPadding)
            })
        }
        chars.forEach { ch ->
            val display = if (shifted) ch.uppercaseChar() else ch
            val typed = if (shifted) ch.uppercaseChar() else ch
            row.addView(qwertyKey(display.toString(), 1f) {
                currentQuery += typed.toString()
                searchInput.text = currentQuery
                applyFilter()
            })
        }
        if (rightPadding > 0f) {
            row.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, 1, rightPadding)
            })
        }
        return row
    }

    /** QWERTY 字母键：圆角、keyBg 背景。 */
    private fun qwertyKey(label: String, weight: Float, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            textSize = QWERTY_TEXT_SIZE
            gravity = Gravity.CENTER
            setTextColor(theme.text)
            typeface = Typeface.DEFAULT
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP))
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
            textSize = FUNC_TEXT_SIZE
            gravity = Gravity.CENTER
            setTextColor(theme.subText)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP))
            layoutParams = lp
            isClickable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
    }

    /** Shift 键：点击切换大小写，选中态用 accent 背景。 */
    private fun shiftKey(weight: Float): View {
        return TextView(this).apply {
            text = "⇧"
            textSize = FUNC_TEXT_SIZE
            gravity = Gravity.CENTER
            setTextColor(if (shiftEnabled) theme.onAccent else theme.subText)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(if (shiftEnabled) theme.accent else theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP))
            layoutParams = lp
            isClickable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                shiftEnabled = !shiftEnabled
                // 重建 QWERTY 键盘以刷新键帽
                val wasQwerty = qwertyMode
                contentContainer.removeAllViews()
                contentContainer.addView(buildQwertyKeyboard())
                qwertyMode = true
            }
        }
    }

    /** QWERTY 强调键（如"完成"）：accent 背景。 */
    private fun accentKey(label: String, weight: Float, onClick: () -> Unit): View {
        return TextView(this).apply {
            text = label
            textSize = FUNC_TEXT_SIZE
            gravity = Gravity.CENTER
            setTextColor(theme.onAccent)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.accent)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight)
            lp.setMargins(dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP), dp(QWERTY_GAP_DP))
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
        btnFavorite.isEnabled = true
        btnShare.alpha = 1f
        btnAccessibility.alpha = 1f
        btnFavorite.alpha = 1f
        btnFavorite.setColorFilter(
            if (meme.isFavorite) theme.accent else theme.subText
        )
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
            rebuildCategories()
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
