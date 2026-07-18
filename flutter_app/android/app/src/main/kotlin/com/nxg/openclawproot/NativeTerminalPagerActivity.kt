package com.agent.cyx

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.GestureDetector
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding

class NativeTerminalPagerActivity : Activity() {
    private lateinit var launchGroupId: String
    private lateinit var baseConfig: NativeTerminalSessionConfig
    private lateinit var rootLayout: LinearLayout
    private lateinit var titleView: TextView
    private lateinit var pageHintView: TextView
    private lateinit var sessionBadgeView: TextView
    private lateinit var sessionSwitcherView: FrameLayout
    private lateinit var terminalTabButton: FrameLayout
    private lateinit var browserTabButton: FrameLayout
    private lateinit var newSessionButton: FrameLayout
    private lateinit var pasteButton: FrameLayout
    private lateinit var restartButton: FrameLayout
    private lateinit var closeSessionButton: FrameLayout
    private lateinit var terminalPage: FrameLayout
    private lateinit var browserPage: FrameLayout
    private lateinit var pagesContainer: FrameLayout
    private lateinit var terminalContainer: FrameLayout
    private lateinit var browserView: NativeCodexBrowserView
    private var activeTerminalView: NativeTerminalSessionView? = null
    private val sessions = mutableListOf<NativeTerminalSessionConfig>()
    private var activeIndex = 0
    private var activePageIndex = PAGE_TERMINAL
    private var closedAllSessions = false
    private val pagerGestureDetector by lazy {
        GestureDetector(
            this,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onFling(
                    e1: MotionEvent?,
                    e2: MotionEvent,
                    velocityX: Float,
                    velocityY: Float,
                ): Boolean {
                    val start = e1 ?: return false
                    val dx = e2.x - start.x
                    val dy = e2.y - start.y
                    if (kotlin.math.abs(dx) < dp(64) || kotlin.math.abs(dx) < kotlin.math.abs(dy) * 1.2f) {
                        return false
                    }
                    if (dx < 0) {
                        showPage(PAGE_BROWSER)
                    } else {
                        showPage(PAGE_TERMINAL)
                    }
                    return true
                }
            },
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val parsedConfig = parseIntentConfig(intent) ?: run {
            finish()
            return
        }
        baseConfig = parsedConfig.copy(
            keepAlive = true,
            useNativeToolbar = true,
            useCodexChrome = true,
        )
        launchGroupId = parsedConfig.sessionId
        val savedSessionsForGroup = savedSessions[launchGroupId]
        if (savedInstanceState == null && !savedSessionsForGroup.isNullOrEmpty()) {
            sessions.addAll(savedSessionsForGroup.map {
                it.copy(
                    keepAlive = true,
                    useNativeToolbar = true,
                    useCodexChrome = true,
                    restart = false,
                )
            })
            activeIndex = (savedActiveIndexes[launchGroupId] ?: 0)
                .coerceIn(0, sessions.lastIndex)
        } else {
            sessions.add(baseConfig)
        }

        setResult(Activity.RESULT_OK)
        TerminalSessionService.start(applicationContext)
        setContentView(createContentView())
        NativeBrowserAutomationRegistry.controller = browserView
        showSession(activeIndex, restart = baseConfig.restart)
        showPage(PAGE_TERMINAL)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        pagerGestureDetector.onTouchEvent(event)
        return super.dispatchTouchEvent(event)
    }

    override fun onBackPressed() {
        if (activePageIndex == PAGE_BROWSER) {
            if (browserView.handleBackPressed()) {
                return
            }
            showPage(PAGE_TERMINAL)
            return
        }
        finish()
    }

    override fun onDestroy() {
        if (NativeBrowserAutomationRegistry.controller === browserView) {
            NativeBrowserAutomationRegistry.controller = null
        }
        browserView.dispose()
        if (!closedAllSessions) {
            persistSessions()
            activeTerminalView?.dispose(closeSession = false)
        } else {
            activeTerminalView?.dispose(closeSession = true)
        }
        activeTerminalView = null
        TerminalSessionService.stop(applicationContext)
        super.onDestroy()
    }

    private fun createContentView(): View {
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(NativeUiPalette.background)
            clipToPadding = false
        }

        titleView = TextView(this).apply {
            setTextColor(NativeUiPalette.textPrimary)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        }
        pageHintView = TextView(this).apply {
            setTextColor(NativeUiPalette.textMuted)
            textSize = 11.5f
            typeface = Typeface.MONOSPACE
            text = "左滑切到浏览器 · 右滑回终端"
        }
        sessionBadgeView = TextView(this).apply {
            setTextColor(NativeUiPalette.textMuted)
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(8), dp(3), dp(8), dp(3))
            background = nativeCardDrawable(
                fillColor = NativeUiPalette.surfaceRaised,
                strokeColor = NativeUiPalette.borderStrong,
                radiusDp = 8,
            )
            visibility = View.GONE
        }
        sessionSwitcherView = createIconActionButton(R.drawable.lucide_layout_list, "切换会话") { showSessionMenu(it) }
        terminalTabButton = createIconActionButton(R.drawable.lucide_audio_waveform, "终端") { showPage(PAGE_TERMINAL) }
        browserTabButton = createIconActionButton(R.drawable.lucide_panel_top_open, "浏览器") { showPage(PAGE_BROWSER) }
        newSessionButton = createIconActionButton(R.drawable.lucide_plus, "新建会话") { openNewSession() }
        pasteButton = createIconActionButton(R.drawable.lucide_clipboard_paste, "粘贴") { activeTerminalView?.paste() }
        restartButton = createIconActionButton(R.drawable.lucide_refresh_cw, "重开会话") { activeTerminalView?.restart() }
        closeSessionButton = createIconActionButton(R.drawable.lucide_x, "关闭会话") { closeCurrentSession() }

        terminalContainer = FrameLayout(this)
        browserView = NativeCodexBrowserView(this)
        terminalPage = FrameLayout(this).apply {
            setBackgroundColor(NativeUiPalette.background)
            addView(
                terminalContainer,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        browserPage = FrameLayout(this).apply {
            setBackgroundColor(NativeUiPalette.background)
            addView(
                browserView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }

        rootLayout.addView(createTitleRow())
        rootLayout.addView(createActionRow())
        pagesContainer = FrameLayout(this).apply {
            setBackgroundColor(NativeUiPalette.background)
            addView(
                terminalPage,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                browserPage,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        rootLayout.addView(
            pagesContainer,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ).apply {
                topMargin = dp(2)
            },
        )

        bindWindowInsets()
        return rootLayout
    }

    private fun bindWindowInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
            val navigationBars = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            val imeBottom = (imeInsets.bottom - navigationBars.bottom).coerceAtLeast(0)
            val imeVisible = insets.isVisible(WindowInsetsCompat.Type.ime()) && imeBottom > 0
            view.updatePadding(
                left = systemBars.left,
                top = systemBars.top,
                right = systemBars.right,
                bottom = 0,
            )
            pagesContainer.updatePadding(bottom = if (imeVisible) imeBottom else systemBars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(rootLayout)
    }

    private fun createTitleRow(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = nativeCardDrawable(
                fillColor = NativeUiPalette.surface,
                strokeColor = NativeUiPalette.border,
                radiusDp = 10,
            )
            setPadding(dp(10), dp(10), dp(10), dp(8))
            addView(createIconActionButton(R.drawable.lucide_chevron_left, "返回") { finish() })
            addView(
                LinearLayout(this@NativeTerminalPagerActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(titleView)
                    addView(pageHintView)
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = dp(10)
                    marginEnd = dp(8)
                },
            )
            addView(sessionBadgeView)
            addView(createIconActionButton(R.drawable.lucide_panel_top_close, "退出") {
                // Keep sessions alive for reopen; only the explicit close-session path tears them down.
                finish()
            })
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(6)
                marginEnd = dp(6)
                topMargin = dp(6)
            }
        }
    }

    private fun createActionRow(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            addView(terminalTabButton)
            addView(browserTabButton)
            addView(sessionSwitcherView)
            addView(newSessionButton)
            addView(pasteButton)
            addView(restartButton)
            addView(closeSessionButton)
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setBackgroundColor(NativeUiPalette.background)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(6)
                marginEnd = dp(6)
                topMargin = dp(3)
            }
            addView(
                row,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
    }

    private fun createIconActionButton(
        iconRes: Int,
        description: String,
        onClick: (View) -> Unit,
    ): FrameLayout {
        return FrameLayout(this).apply {
            contentDescription = description
            minimumWidth = dp(38)
            minimumHeight = dp(34)
            isClickable = true
            isFocusable = true
            isHapticFeedbackEnabled = true
            background = actionButtonDrawable(NativeUiPalette.surfaceRaised)
            val iconDrawable = ContextCompat.getDrawable(this@NativeTerminalPagerActivity, iconRes)?.mutate()
            if (iconDrawable != null) {
                DrawableCompat.setTint(iconDrawable, NativeUiPalette.textPrimary)
            }
            addView(
                ImageView(this@NativeTerminalPagerActivity).apply {
                    setImageDrawable(iconDrawable)
                    this.contentDescription = description
                },
                FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER),
            )
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick(it)
            }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(
                dp(38),
                dp(34),
            ).apply {
                marginEnd = dp(4)
            }
        }
    }

    private fun actionButtonDrawable(color: Int) =
        nativeRoundedStateDrawable(
            normalColor = color,
            pressedColor = NativeUiPalette.borderStrong,
            selectedColor = NativeUiPalette.accentSoft,
            selectedPressedColor = NativeUiPalette.accentPressed,
            strokeColor = NativeUiPalette.border,
            selectedStrokeColor = NativeUiPalette.accent,
            radiusDp = 8,
        )

    private fun showSession(index: Int, restart: Boolean = false) {
        if (index !in sessions.indices) {
            return
        }
        activeTerminalView?.dispose(closeSession = false)
        terminalContainer.removeAllViews()

        activeIndex = index
        val targetConfig = sessions[index].copy(
            restart = restart,
            keepAlive = true,
            useNativeToolbar = true,
            useCodexChrome = true,
        )
        val sessionView = NativeTerminalSessionView(
            context = this,
            appContext = applicationContext,
            config = targetConfig,
            callbacks = object : NativeTerminalSessionCallbacks {
                override fun onTitleChanged(title: String) {
                    if (title.isBlank()) {
                        return
                    }
                    sessions[activeIndex] = sessions[activeIndex].copy(title = title)
                    updateChrome()
                }
            },
        )
        activeTerminalView = sessionView
        terminalContainer.addView(
            sessionView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        updateChrome()
        if (activePageIndex == PAGE_TERMINAL) {
            sessionView.post { sessionView.requestToolbarVisible() }
        }
    }

    private fun openNewSession() {
        val nextNumber = sessions.size + 1
        sessions.add(
            baseConfig.copy(
                sessionId = "$launchGroupId-${System.currentTimeMillis()}",
                title = "${baseConfig.title} $nextNumber",
                restart = false,
                keepAlive = true,
                useNativeToolbar = true,
                useCodexChrome = true,
            ),
        )
        showSession(sessions.lastIndex)
        showPage(PAGE_TERMINAL)
        persistSessions()
    }

    private fun closeCurrentSession() {
        val currentView = activeTerminalView
        if (currentView == null) {
            finish()
            return
        }
        currentView.closeSession()
        currentView.dispose(closeSession = true)
        activeTerminalView = null
        terminalContainer.removeAllViews()

        if (sessions.size <= 1) {
            savedSessions.remove(launchGroupId)
            savedActiveIndexes.remove(launchGroupId)
            closedAllSessions = true
            finish()
            return
        }

        sessions.removeAt(activeIndex)
        if (activeIndex > sessions.lastIndex) {
            activeIndex = sessions.lastIndex
        }
        showSession(activeIndex)
        persistSessions()
    }

    private fun showSessionMenu(anchor: View) {
        val popup = PopupMenu(this, anchor)
        sessions.forEachIndexed { index, session ->
            val prefix = if (index == activeIndex) "● " else "○ "
            popup.menu.add(0, index, index, prefix + session.title)
        }
        popup.menu.add(1, MENU_NEW_SESSION, sessions.size, "新建会话")
        popup.setOnMenuItemClickListener { item ->
            if (item.itemId == MENU_NEW_SESSION) {
                openNewSession()
            } else {
                showSession(item.itemId)
                showPage(PAGE_TERMINAL)
            }
            true
        }
        popup.show()
    }

    private fun persistSessions() {
        if (sessions.isEmpty()) {
            savedSessions.remove(launchGroupId)
            savedActiveIndexes.remove(launchGroupId)
            return
        }
        savedSessions[launchGroupId] = sessions.map {
            it.copy(
                restart = false,
                keepAlive = true,
                useNativeToolbar = true,
                useCodexChrome = true,
            )
        }
        savedActiveIndexes[launchGroupId] = activeIndex
    }

    private fun showPage(index: Int) {
        activePageIndex = if (index == PAGE_BROWSER) PAGE_BROWSER else PAGE_TERMINAL
        terminalPage.visibility = if (activePageIndex == PAGE_TERMINAL) View.VISIBLE else View.GONE
        browserPage.visibility = if (activePageIndex == PAGE_BROWSER) View.VISIBLE else View.GONE
        terminalTabButton.isSelected = activePageIndex == PAGE_TERMINAL
        browserTabButton.isSelected = activePageIndex == PAGE_BROWSER
        val terminalControlsVisible = if (activePageIndex == PAGE_TERMINAL) View.VISIBLE else View.GONE
        sessionSwitcherView.visibility = terminalControlsVisible
        newSessionButton.visibility = terminalControlsVisible
        pasteButton.visibility = terminalControlsVisible
        restartButton.visibility = terminalControlsVisible
        closeSessionButton.visibility = terminalControlsVisible
        if (activePageIndex == PAGE_TERMINAL) {
            activeTerminalView?.post { activeTerminalView?.requestToolbarVisible() }
        }
        updateChrome()
    }

    private fun updateChrome() {
        val activeSession = sessions.getOrNull(activeIndex)
        if (activePageIndex == PAGE_TERMINAL) {
            titleView.text = activeSession?.title ?: baseConfig.title
            pageHintView.text = "左滑切到浏览器 · 右滑回终端"
        } else {
            titleView.text = "Codex 浏览器"
            pageHintView.text = "脚本助手在更多菜单 · 右滑回终端"
        }
        val multipleSessions = sessions.size > 1
        sessionBadgeView.visibility = if (multipleSessions && activePageIndex == PAGE_TERMINAL) {
            View.VISIBLE
        } else {
            View.GONE
        }
        sessionBadgeView.text = "${activeIndex + 1}/${sessions.size}"
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val EXTRA_SESSION_ID = "native_terminal.session_id"
        private const val EXTRA_TITLE = "native_terminal.title"
        private const val EXTRA_EXECUTABLE = "native_terminal.executable"
        private const val EXTRA_CWD = "native_terminal.cwd"
        private const val EXTRA_ARGUMENTS = "native_terminal.arguments"
        private const val EXTRA_ENVIRONMENT = "native_terminal.environment"
        private const val EXTRA_RESTART = "native_terminal.restart"
        private const val EXTRA_KEEP_ALIVE = "native_terminal.keep_alive"
        private const val EXTRA_EMIT_OUTPUT = "native_terminal.emit_output"
        private const val EXTRA_RENDERING_PAUSED = "native_terminal.rendering_paused"
        private const val EXTRA_USE_NATIVE_TOOLBAR = "native_terminal.use_native_toolbar"
        private const val EXTRA_TRANSCRIPT_ROWS = "native_terminal.transcript_rows"
        private const val EXTRA_FONT_SIZE = "native_terminal.font_size"
        private const val PAGE_TERMINAL = 0
        private const val PAGE_BROWSER = 1
        private const val MENU_NEW_SESSION = 10_001

        private val savedSessions = mutableMapOf<String, List<NativeTerminalSessionConfig>>()
        private val savedActiveIndexes = mutableMapOf<String, Int>()

        fun createIntent(context: Context, config: NativeTerminalSessionConfig): Intent {
            return Intent(context, NativeTerminalPagerActivity::class.java).apply {
                putExtra(EXTRA_SESSION_ID, config.sessionId)
                putExtra(EXTRA_TITLE, config.title)
                putExtra(EXTRA_EXECUTABLE, config.executable)
                putExtra(EXTRA_CWD, config.cwd)
                putStringArrayListExtra(EXTRA_ARGUMENTS, ArrayList(config.arguments))
                putExtra(EXTRA_ENVIRONMENT, HashMap(config.environment))
                putExtra(EXTRA_RESTART, config.restart)
                putExtra(EXTRA_KEEP_ALIVE, config.keepAlive)
                putExtra(EXTRA_EMIT_OUTPUT, config.emitOutput)
                putExtra(EXTRA_RENDERING_PAUSED, config.renderingPaused)
                putExtra(EXTRA_USE_NATIVE_TOOLBAR, config.useNativeToolbar)
                putExtra(EXTRA_TRANSCRIPT_ROWS, config.transcriptRows)
                putExtra(EXTRA_FONT_SIZE, config.fontSize)
            }
        }

        fun parseIntentConfig(intent: Intent): NativeTerminalSessionConfig? {
            val executable = intent.getStringExtra(EXTRA_EXECUTABLE) ?: return null
            return NativeTerminalSessionConfig(
                sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: "native-shell",
                title = intent.getStringExtra(EXTRA_TITLE) ?: "Terminal",
                executable = executable,
                cwd = intent.getStringExtra(EXTRA_CWD) ?: "/",
                arguments = intent.getStringArrayListExtra(EXTRA_ARGUMENTS) ?: arrayListOf(),
                environment = (intent.getSerializableExtra(EXTRA_ENVIRONMENT) as? HashMap<*, *>)
                    ?.mapNotNull { (key, value) ->
                        val stringKey = key as? String
                        val stringValue = value as? String
                        if (stringKey != null && stringValue != null) stringKey to stringValue else null
                    }
                    ?.toMap()
                    ?: emptyMap(),
                restart = intent.getBooleanExtra(EXTRA_RESTART, false),
                keepAlive = intent.getBooleanExtra(EXTRA_KEEP_ALIVE, true),
                emitOutput = intent.getBooleanExtra(EXTRA_EMIT_OUTPUT, false),
                renderingPaused = intent.getBooleanExtra(EXTRA_RENDERING_PAUSED, false),
                useNativeToolbar = intent.getBooleanExtra(EXTRA_USE_NATIVE_TOOLBAR, true),
                transcriptRows = intent.getIntExtra(EXTRA_TRANSCRIPT_ROWS, 3000),
                fontSize = intent.getIntExtra(EXTRA_FONT_SIZE, 18),
            )
        }
    }
}
