package com.mako.mako_meme.ime

import android.inputmethodservice.InputMethodService
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView

/**
 * Mako 表情包输入法服务。
 *
 * 键盘布局（代码构建，无 XML）：
 * ```
 * ┌──────────────────────────────────────────────┐
 * │ [切换输入法] [键盘] [分享发送] [无障碍发送]    │ ← 操作栏
 * │ [全部][表情][GIF][图片][文字][角色卡][立绘][CG]│ ← 分类 Tab（可横向滚动）
 * │ [搜索表情包名称 / 标签...                    ]│ ← 搜索框
 * │ ┌──┐┌──┐┌──┐┌──┐                            │
 * │ │  ││  ││  ││  │  ...（4 列网格）           │
 * │ └──┘└──┘└──┘└──┘                            │
 * └──────────────────────────────────────────────┘
 * ```
 *
 * - 点击 meme 条目 → [onMemeClicked]，选中后高亮并启用发送按钮。
 * - 「切换输入法」→ [switchToPreviousInputMethod]。
 * - 「键盘」→ 切换到 QWERTY 键盘模式，用于输入搜索关键字。
 * - 「分享发送」→ [MemeSender.sendViaShare]。
 * - 「无障碍发送」→ [MemeSender.sendViaAccessibility]。
 * - 配色由 [ImeTheme] 从主应用同步，高度约 280dp。
 */
class MakoImeService : InputMethodService() {

    companion object {
        /** 键盘高度（dp）。 */
        private const val KEYBOARD_HEIGHT_DP = 280
        /** 网格列数。 */
        private const val GRID_SPAN = 4
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

    private lateinit var btnShare: Button
    private lateinit var btnAccessibility: Button
    private lateinit var btnKeyboard: Button
    private lateinit var searchInput: EditText
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
        adapter = MemeGridAdapter(this) { meme -> onMemeClicked(meme) }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(KEYBOARD_HEIGHT_DP)
            )
            setBackgroundColor(theme.bg)
        }

        root.addView(buildActionBar())
        root.addView(buildCategoryTabs())
        root.addView(buildSearchBar())

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

    /** 第一行：操作按钮（切换 / 键盘 / 分享 / 无障碍）。 */
    private fun buildActionBar(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(38)
            )
            setPadding(dp(6), dp(4), dp(6), dp(4))
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(theme.surface)

            val btnSwitch = Button(this@MakoImeService).apply {
                text = "切换"
                textSize = 11f
                setTextColor(theme.text)
                setBackgroundColor(theme.accent)
                setOnClickListener {
                    val switched = switchToPreviousInputMethod()
                    if (!switched) {
                        Toast.makeText(this@MakoImeService, "没有上一个输入法", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            addView(btnSwitch)

            btnKeyboard = Button(this@MakoImeService).apply {
                text = "键盘"
                textSize = 11f
                setTextColor(theme.text)
                setBackgroundColor(theme.surface)
                setOnClickListener { toggleQwerty() }
            }
            addView(btnKeyboard)

            btnShare = Button(this@MakoImeService).apply {
                text = "分享发送"
                textSize = 11f
                setTextColor(theme.text)
                setBackgroundColor(theme.surface)
                isEnabled = false
                setOnClickListener {
                    val meme = selectedMeme
                    if (meme != null) {
                        MemeSender.sendViaShare(this@MakoImeService, meme)
                    } else {
                        Toast.makeText(this@MakoImeService, "请先选择一个表情", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            addView(btnShare)

            btnAccessibility = Button(this@MakoImeService).apply {
                text = "无障碍发送"
                textSize = 11f
                setTextColor(theme.text)
                setBackgroundColor(theme.surface)
                isEnabled = false
                setOnClickListener {
                    val meme = selectedMeme
                    if (meme != null) {
                        MemeSender.sendViaAccessibility(this@MakoImeService, meme)
                    } else {
                        Toast.makeText(this@MakoImeService, "请先选择一个表情", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            addView(btnAccessibility)

            // 占位撑开，让按钮左对齐
            val spacer = View(this@MakoImeService).apply {
                layoutParams = LinearLayout.LayoutParams(0, dp(1), 1f)
            }
            addView(spacer)
        }
    }

    /** 第二行：分类 Tab（横向可滚动）。 */
    private fun buildCategoryTabs(): View {
        tabViews.clear()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(2), dp(6), dp(2))
        }
        categories.forEach { (label, type) ->
            val tab = TextView(this).apply {
                text = label
                textSize = 13f
                setPadding(dp(12), dp(4), dp(12), dp(4))
                setTextColor(theme.subText)
                isClickable = true
                setOnClickListener {
                    currentType = type
                    updateTabHighlight(this)
                    applyFilter()
                }
            }
            tabViews.add(tab)
            row.addView(tab)
        }
        // 默认高亮"全部"
        updateTabHighlight(tabViews.first())

        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(34)
            )
        }
    }

    /** 第三行：搜索框。 */
    private fun buildSearchBar(): View {
        searchInput = EditText(this).apply {
            hint = "搜索表情包名称 / 标签..."
            textSize = 13f
            setSingleLine(true)
            setTextColor(theme.text)
            setHintTextColor(theme.subText)
            setBackgroundResource(android.R.color.transparent)
            setPadding(dp(10), dp(2), dp(10), dp(2))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(34)
            )
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    currentQuery = s?.toString() ?: ""
                    applyFilter()
                }
            })
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
            setPadding(dp(4), dp(4), dp(4), dp(4))
            setBackgroundColor(theme.bg)
        }
        return recyclerView
    }

    /** QWERTY 键盘视图：用于输入搜索关键字。 */
    private fun buildQwertyKeyboard(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(dp(4), dp(4), dp(4), dp(4))
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
                val key = Button(this).apply {
                    text = ch.toString()
                    textSize = 16f
                    setTextColor(theme.text)
                    setBackgroundColor(theme.surface)
                    val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f)
                    lp.setMargins(dp(2), dp(2), dp(2), dp(2))
                    layoutParams = lp
                    setOnClickListener {
                        searchInput.text.insert(searchInput.selectionStart.coerceAtLeast(0), ch.toString())
                    }
                }
                rowView.addView(key)
            }
            root.addView(rowView)
        }
        // 最后一行：退格 + 空格 + 切换回表情
        val lastRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        val backspace = Button(this).apply {
            text = "⌫"
            textSize = 16f
            setTextColor(theme.text)
            setBackgroundColor(theme.surface)
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1.5f)
            lp.setMargins(dp(2), dp(2), dp(2), dp(2))
            layoutParams = lp
            setOnClickListener {
                val pos = searchInput.selectionStart.coerceAtLeast(0)
                if (pos > 0 && pos <= searchInput.text.length) {
                    searchInput.text.delete(pos - 1, pos)
                }
            }
        }
        lastRow.addView(backspace)
        val space = Button(this).apply {
            text = "空格"
            textSize = 13f
            setTextColor(theme.text)
            setBackgroundColor(theme.surface)
            val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 4f)
            lp.setMargins(dp(2), dp(2), dp(2), dp(2))
            layoutParams = lp
            setOnClickListener {
                searchInput.text.insert(searchInput.selectionStart.coerceAtLeast(0), " ")
            }
        }
        lastRow.addView(space)
        root.addView(lastRow)
        return root
    }

    /** 切换 QWERTY 键盘 / 表情网格。 */
    private fun toggleQwerty() {
        qwertyMode = !qwertyMode
        contentContainer.removeAllViews()
        if (qwertyMode) {
            contentContainer.addView(buildQwertyKeyboard())
            btnKeyboard.text = "表情"
            btnKeyboard.setTextColor(theme.onAccent)
            btnKeyboard.setBackgroundColor(theme.accent)
        } else {
            contentContainer.addView(recyclerView)
            btnKeyboard.text = "键盘"
            btnKeyboard.setTextColor(theme.text)
            btnKeyboard.setBackgroundColor(theme.surface)
        }
    }

    /** 点击 meme 条目：选中并提示。 */
    private fun onMemeClicked(meme: MemeItem) {
        selectedMeme = meme
        btnShare.isEnabled = true
        btnAccessibility.isEnabled = true
        Toast.makeText(this, "已选中: ${meme.name}", Toast.LENGTH_SHORT).show()
    }

    /** 高亮当前选中的 Tab。 */
    private fun updateTabHighlight(selected: TextView) {
        tabViews.forEach { tab ->
            if (tab === selected) {
                tab.setBackgroundColor(theme.tabBg)
                tab.setTextColor(theme.tabText)
            } else {
                tab.setBackgroundColor(0x00000000)
                tab.setTextColor(theme.subText)
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
