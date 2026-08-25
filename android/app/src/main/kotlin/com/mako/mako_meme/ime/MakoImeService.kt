package com.mako.mako_meme.ime

import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Rect
import android.inputmethodservice.InputMethodService
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.ImageView
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
 * │ 🔍 搜索表情包...                    [✕]      │ ← 胶囊搜索框（最顶部）
 * │ [🌐] [⌨] [⌫] [⏱]               [♿]         │ ← 图标化操作栏（紧凑、圆角）
 * │ [全部][最近][表情][GIF][图片]...（横向滚动） │ ← pill Tab（圆角胶囊选中态）
 * │ ┌──┐ ┌──┐ ┌──┐ ┌──┐                         │
 * │ │  │ │  │ │  │ │  │  ...（3 列圆角卡片）    │
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
        /** 实时结果条最大展示条数。 */
        const val MAX_PREVIEW = 12
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

    /** 最近一次点击的 meme（供无障碍按钮使用）。 */
    private var lastClickedMeme: MemeItem? = null

    /** Shift 大写锁定状态。 */
    private var shiftEnabled = false

    /** Tab 视图列表，用于高亮切换。 */
    private val tabViews = mutableListOf<TextView>()

    /** QWERTY 键盘模式（用于搜索输入）。 */
    private var qwertyMode = false

    private lateinit var btnShare: ImageButton
    private lateinit var btnAccessibility: ImageButton
    private lateinit var btnKeyboard: ImageButton
    private lateinit var btnRecent: ImageButton
    private lateinit var searchInput: TextView
    private lateinit var searchRow: LinearLayout
    private lateinit var clearButton: ImageButton
    private lateinit var resultsStrip: HorizontalScrollView
    private lateinit var resultsRow: LinearLayout
    private lateinit var contentContainer: LinearLayout
    private lateinit var outerContainer: ViewGroup

    /** 最近使用模式。 */
    private var recentMode = false

    private val prefs: SharedPreferences by lazy {
        getSharedPreferences("mako_ime", MODE_PRIVATE)
    }

    /** 从 meme 数据动态构建的分类列表（"全部" + "最近" + 存在的类型）。首次加载后重建。 */
    private val dynamicCategories: MutableList<Pair<String, String?>> = mutableListOf("全部" to null, "最近" to "__recent__")

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

    /** 最近使用 meme ID 列表。 */
    private var recentIds: MutableList<String>
        get() {
            val raw = prefs.getString("recent_ids", "") ?: ""
            return if (raw.isEmpty()) mutableListOf()
            else raw.split(",").toMutableList()
        }
        set(value) {
            prefs.edit().putString("recent_ids", value.take(20).joinToString(",")).apply()
        }

    /** 添加 meme 到最近使用列表头部。 */
    private fun addRecent(memeId: String) {
        val ids = recentIds
        ids.remove(memeId)
        ids.add(0, memeId)
        recentIds = ids
    }

    /** 根据已有 meme 数据刷新分类列表。 */
    private fun rebuildCategories() {
        val typesInData = allMemes.map { it.type }.distinct().sorted()
        dynamicCategories.clear()
        dynamicCategories.add("全部" to null)
        dynamicCategories.add("最近" to "__recent__")
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
        recentMode = false
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
        adapter = MemeGridAdapter(this, theme) { meme -> sendMeme(meme) }

        // 动态键盘高度：屏幕高度的 80%，最大 700dp
        val displayMetrics = resources.displayMetrics
        val keyboardHeightPx = minOf(
            (displayMetrics.heightPixels * 0.8f).toInt(),
            dp(700)
        )

        val keyboard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                keyboardHeightPx
            )
            setBackgroundColor(theme.bg)
        }

        keyboard.addView(buildSearchBar())
        keyboard.addView(buildActionBar())
        keyboard.addView(buildCategoryTabs())
        keyboard.addView(buildDivider())

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
        keyboard.addView(contentContainer)

        // 首次加载 meme 数据
        loadMemes()

        // 外层容器：横屏做浮窗，竖屏填满
        outerContainer = buildOuterContainer(keyboard)
        return outerContainer
    }

    /** 横屏浮窗 / 竖屏全宽 + 导航栏内边距。 */
    private fun buildOuterContainer(inner: View): ViewGroup {
        val isLand = isLandscape()
        val navBarHeight = getNavigationBarHeight()
        if (isLand) {
            // 横屏浮窗：70% 宽度，居中，圆角，底部留呼吸空间
            val marginHoriz = dp(48)
            val marginBottom = dp(24)
            val wrapper = FrameLayout(this).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                setBackgroundColor(0x80000000.toInt()) // 半透明遮罩
                setOnClickListener { switchToPreviousInputMethod() }
            }
            inner.layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
                leftMargin = marginHoriz
                rightMargin = marginHoriz
                bottomMargin = marginBottom
            }
            // 浮窗圆角
            inner.setClipToOutline(true)
            inner.outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(16).toFloat())
                }
            }
            wrapper.addView(inner)
            return wrapper
        } else {
            // 竖屏全宽，底部加导航栏内边距
            inner.setPadding(0, 0, 0, navBarHeight)
            return inner as ViewGroup
        }
    }

    /** 获取导航栏高度（像素）。 */
    private fun getNavigationBarHeight(): Int {
        val res = resources
        val id = res.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) res.getDimensionPixelSize(id) else 0
    }

    /** 判断当前是否为横屏。 */
    private fun isLandscape(): Boolean {
        return resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    }

    /** 屏幕方向变化时重建输入视图。 */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // 重建整个输入视图以切换竖屏/横屏布局
        setInputView(onCreateInputView())
    }

    /** 向系统报告 IME 可见区域，确保应用内容正确抬升。 */
    override fun onComputeInsets(outInsets: Insets) {
        super.onComputeInsets(outInsets)
        // 触摸区域 = 可见区域（导航栏外不响应触摸）
        outInsets.touchableInsets = Insets.TOUCHABLE_INSETS_VISIBLE
        // visibleTopInsets 保持默认（全可见），让系统正确计算内容偏移
    }

    /** 第一行：图标化操作栏（切换 / 键盘 / 退格 / 最近使用 / 无障碍）。点击表情直接分享，无需手动按分享按钮。 */
    private fun buildActionBar(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(36)
            )
            setPadding(dp(8), dp(2), dp(8), dp(2))
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
                    updateClearButton()
                    applyFilter()
                }
            })
            addView(spacer(dp(4)))
            // 最近使用
            btnRecent = iconButton(android.R.drawable.ic_menu_myplaces, "最近使用") {
                recentMode = !recentMode
                if (recentMode) {
                    btnRecent.background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(theme.accent)
                        cornerRadius = dp(KEY_RADIUS_DP).toFloat()
                    }
                    btnRecent.imageTintList = android.content.res.ColorStateList.valueOf(theme.onAccent)
                } else {
                    btnRecent.background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(theme.keyFuncBg)
                        cornerRadius = dp(KEY_RADIUS_DP).toFloat()
                    }
                    btnRecent.imageTintList = android.content.res.ColorStateList.valueOf(theme.text)
                }
                applyFilter()
            }
            addView(btnRecent)

            // 中间撑开
            addView(View(this@MakoImeService).apply {
                layoutParams = LinearLayout.LayoutParams(0, dp(1), 1f)
            })

            // 右侧：无障碍发送（点击表情直接系统分享，无障碍按钮用于第三方 App 自动发送）
            btnAccessibility = iconButton(android.R.drawable.ic_menu_help, "无障碍发送") {
                val meme = lastClickedMeme
                if (meme != null) {
                    MemeSender.sendViaAccessibility(this@MakoImeService, meme)
                } else {
                    Toast.makeText(this@MakoImeService, "请先点击一个表情", Toast.LENGTH_SHORT).show()
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
                    if (type == "__recent__") {
                        recentMode = true
                        currentType = null
                    } else {
                        currentType = type
                        recentMode = false
                    }
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

    /** 第三行：搜索框（胶囊形，点击切换到 QWERTY；有输入时尾部显示清空按钮）。 */
    private fun buildSearchBar(): View {
        searchInput = TextView(this).apply {
            text = currentQuery
            hint = "搜索表情包名称 / 标签..."
            textSize = 13f
            setSingleLine(true)
            setTextColor(theme.text)
            setHintTextColor(theme.subText)
            setPadding(dp(14), dp(8), dp(44), dp(8))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.surface)
                cornerRadius = dp(16).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(36)
            )
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
        clearButton = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.keyFuncBg)
                cornerRadius = dp(KEY_RADIUS_DP).toFloat()
            }
            imageTintList = android.content.res.ColorStateList.valueOf(theme.subText)
            setPadding(dp(6), dp(4), dp(6), dp(4))
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28))
            isClickable = true
            visibility = View.GONE
            setOnClickListener {
                currentQuery = ""
                searchInput.text = currentQuery
                updateClearButton()
                applyFilter()
            }
        }
        searchRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(36)
            ).apply { setMargins(dp(8), dp(2), dp(8), dp(4)) }
            addView(searchInput)
            addView(clearButton)
        }
        return searchRow
    }

    /** 刷新清空按钮可见性。 */
    private fun updateClearButton() {
        clearButton.visibility = if (currentQuery.isEmpty()) View.GONE else View.VISIBLE
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

    /** 横向实时结果条：QWERTY 模式下键盘上方展示最多 12 个匹配项，点击直接发送。 */
    private fun buildResultsStrip(): View {
        resultsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(2), dp(8), dp(2))
        }
        resultsStrip = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(72)
            ).apply { topMargin = dp(4) }
            visibility = View.GONE
            addView(resultsRow)
        }
        return resultsStrip
    }

    /** 刷新实时结果条（最多展示 [MAX_PREVIEW] 条）。 */
    private fun updateResultsStrip(items: List<MemeItem>) {
        if (!qwertyMode) return
        val preview = items.take(MAX_PREVIEW)
        if (preview.isEmpty()) {
            resultsStrip.visibility = View.GONE
            return
        }
        resultsStrip.visibility = View.VISIBLE
        resultsRow.removeAllViews()
        preview.forEach { meme ->
            resultsRow.addView(buildResultCard(meme))
            resultsRow.addView(spacer(dp(6)))
        }
    }

    /** 构建结果条中的单个卡片。 */
    private fun buildResultCard(meme: MemeItem): View {
        val card = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(theme.cardBg)
                cornerRadius = dp(8).toFloat()
            }
        }
        val content: View = if (meme.isImage) {
            ImageView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = ImageView.ScaleType.CENTER_CROP
                clipToOutline = true
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: android.graphics.Outline) {
                        outline.setRoundRect(0, 0, view.width, view.height, dp(8).toFloat())
                    }
                }
                if (meme.absPath.isNotEmpty()) {
                    BitmapLoader.load(meme.absPath, this, dp(56))
                }
            }
        } else {
            TextView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                gravity = Gravity.CENTER
                setTextColor(theme.text)
                textSize = 10f
                setPadding(dp(4), dp(4), dp(4), dp(4))
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                text = meme.textContent?.takeIf { it.isNotBlank() } ?: meme.name
            }
        }
        card.addView(content)
        card.setOnClickListener { sendMeme(meme) }
        return card
    }

    /**
     * QWERTY 键盘视图：圆角按键，参考系统输入法 / Rime 布局。
     *
     * 布局（自上而下）：
     * ```
     * [实时结果条：最多 12 个匹配缩略图]
     *  q w e r t y u i o p
     *   a s d f g h j k l
     *  ⇧ z x c v b n m  ⌫
     *  [😀]   空格    [完成]
     * ```
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
        // 顶部实时结果条
        root.addView(buildResultsStrip())
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
                updateClearButton()
                applyFilter()
            })
        }
        // 右侧删除键（与下方"完成"键宽度一致，垂直对齐）
        row3.addView(funcKey("⌫", 1.5f) {
            if (currentQuery.isNotEmpty()) {
                currentQuery = currentQuery.dropLast(1)
                searchInput.text = currentQuery
                updateClearButton()
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
            updateClearButton()
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
                updateClearButton()
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

    /** 点击 meme 条目：优先直插聊天框（微信路径上屏 / commitContent），失败则回退系统分享。 */
    private fun sendMeme(meme: MemeItem) {
        lastClickedMeme = meme
        btnAccessibility.isEnabled = true
        btnAccessibility.alpha = 1f
        addRecent(meme.id)
        val ic = currentInputConnection
        val ei = currentInputEditorInfo
        if (ic != null && ei != null) {
            if (MemeInserter.tryInsert(this, meme, ic, ei)) return
        }
        MemeSender.sendViaShare(this, meme)
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
        // 最近使用模式
        if (recentMode) {
            val ids = recentIds
            val idSet = ids.toSet()
            filtered = filtered.filter { it.id in idSet }
            // 按最近使用顺序排列
            val order = ids.withIndex().associate { (i, id) -> id to i }
            filtered = filtered.sortedBy { order[it.id] ?: Int.MAX_VALUE }
        }
        // 按分类过滤
        if (currentType != null) {
            filtered = filtered.filter { it.type == currentType }
        }
        // 按搜索关键字过滤
        filtered = repository.search(currentQuery, filtered)
        adapter.submit(filtered)
        updateResultsStrip(filtered)
    }

    /** 横屏时禁止系统把 IME 切到全屏 extract 模式，保证浮窗布局始终生效。 */
    override fun onEvaluateFullscreenMode(): Boolean = false

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
