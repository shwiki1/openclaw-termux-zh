package com.agent.cyx

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding

class NativeTerminalPagerActivity : Activity() {
    private lateinit var baseConfig: NativeTerminalSessionConfig
    private lateinit var rootLayout: LinearLayout
    private lateinit var titleView: TextView
    private lateinit var pageHintView: TextView
    private lateinit var terminalTabButton: TextView
    private lateinit var browserTabButton: TextView
    private lateinit var pasteButton: TextView
    private lateinit var restartButton: TextView
    private lateinit var terminalPage: FrameLayout
    private lateinit var browserPage: FrameLayout
    private lateinit var pagesContainer: FrameLayout
    private lateinit var terminalView: NativeTerminalSessionView
    private lateinit var browserView: NativeCodexBrowserView
    private var activePageIndex = PAGE_TERMINAL
    private var terminalTitle = "Terminal"
    private var sessionClosed = false
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
        baseConfig = parsedConfig.copy(keepAlive = true, useNativeToolbar = true)
        terminalTitle = parsedConfig.title
        setResult(Activity.RESULT_OK)
        TerminalSessionService.start(applicationContext)
        setContentView(createContentView())
        NativeBrowserAutomationRegistry.controller = browserView
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
        if (sessionClosed) {
            terminalView.dispose(closeSession = true)
        } else {
            terminalView.dispose(closeSession = false)
        }
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
            text = terminalTitle
        }
        pageHintView = TextView(this).apply {
            setTextColor(NativeUiPalette.textMuted)
            textSize = 11.5f
            typeface = Typeface.MONOSPACE
            text = "左滑切到浏览器 · 右滑回终端"
        }
        terminalTabButton = createActionButton("终端") { showPage(PAGE_TERMINAL) }
        browserTabButton = createActionButton("浏览器") { showPage(PAGE_BROWSER) }
        pasteButton = createActionButton("粘贴") { terminalView.paste() }
        restartButton = createActionButton("重开") { terminalView.restart() }

        terminalView = NativeTerminalSessionView(
            context = this,
            appContext = applicationContext,
            config = baseConfig,
            callbacks = object : NativeTerminalSessionCallbacks {
                override fun onTitleChanged(title: String) {
                    if (title.isBlank()) {
                        return
                    }
                    terminalTitle = title
                    updateChrome()
                }
            },
        )

        browserView = NativeCodexBrowserView(this)
        terminalPage = FrameLayout(this).apply {
            setBackgroundColor(NativeUiPalette.background)
            addView(
                terminalView,
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
            background = nativeCardDrawable(
                fillColor = NativeUiPalette.surface,
                strokeColor = NativeUiPalette.borderStrong,
                radiusDp = 22,
            )
            clipToOutline = true
            setPadding(dp(1), dp(1), dp(1), dp(1))
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
                marginStart = dp(12)
                marginEnd = dp(12)
                topMargin = dp(6)
                bottomMargin = dp(12)
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
                radiusDp = 18,
            )
            setPadding(dp(12), dp(12), dp(12), dp(10))
            addView(createActionButton("返回") { finish() })
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
            addView(createActionButton("关闭") {
                sessionClosed = true
                terminalView.closeSession()
                finish()
            })
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(12)
                marginEnd = dp(12)
                topMargin = dp(12)
            }
        }
    }

    private fun createActionRow(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            addView(terminalTabButton)
            addView(browserTabButton)
            addView(pasteButton)
            addView(restartButton)
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            background = nativeCardDrawable(
                fillColor = NativeUiPalette.surfaceAlt,
                strokeColor = NativeUiPalette.border,
                radiusDp = 18,
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(12)
                marginEnd = dp(12)
                topMargin = dp(10)
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

    private fun createActionButton(label: String, onClick: (View) -> Unit): TextView {
        return TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(NativeUiPalette.textPrimary)
            textSize = 12f
            typeface = Typeface.MONOSPACE
            minimumWidth = dp(52)
            minHeight = dp(38)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = actionButtonDrawable(NativeUiPalette.surfaceRaised)
            setOnClickListener { onClick(it) }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginEnd = dp(6)
            }
        }
    }

    private fun actionButtonDrawable(color: Int) =
        nativeCardDrawable(fillColor = color, strokeColor = NativeUiPalette.borderStrong, radiusDp = 14)

    private fun showPage(index: Int) {
        activePageIndex = if (index == PAGE_BROWSER) PAGE_BROWSER else PAGE_TERMINAL
        terminalPage.visibility = if (activePageIndex == PAGE_TERMINAL) View.VISIBLE else View.GONE
        browserPage.visibility = if (activePageIndex == PAGE_BROWSER) View.VISIBLE else View.GONE
        terminalTabButton.background = actionButtonDrawable(
            if (activePageIndex == PAGE_TERMINAL) NativeUiPalette.accentSoft else NativeUiPalette.surfaceRaised,
        )
        terminalTabButton.setTextColor(
            if (activePageIndex == PAGE_TERMINAL) NativeUiPalette.accent else NativeUiPalette.textPrimary,
        )
        browserTabButton.background = actionButtonDrawable(
            if (activePageIndex == PAGE_BROWSER) NativeUiPalette.accentSoft else NativeUiPalette.surfaceRaised,
        )
        browserTabButton.setTextColor(
            if (activePageIndex == PAGE_BROWSER) NativeUiPalette.accent else NativeUiPalette.textPrimary,
        )
        pasteButton.visibility = if (activePageIndex == PAGE_TERMINAL) View.VISIBLE else View.GONE
        restartButton.visibility = if (activePageIndex == PAGE_TERMINAL) View.VISIBLE else View.GONE
        if (activePageIndex == PAGE_TERMINAL) {
            terminalView.post { terminalView.requestToolbarVisible() }
        }
        updateChrome()
    }

    private fun updateChrome() {
        titleView.text = if (activePageIndex == PAGE_TERMINAL) {
            terminalTitle
        } else {
            "Codex 浏览器"
        }
        pageHintView.text = if (activePageIndex == PAGE_TERMINAL) {
            "左滑切到浏览器 · 右滑回终端"
        } else {
            "浏览器功能已切回原生布局 · 右滑回终端"
        }
        pasteButton.setTextColor(NativeUiPalette.textPrimary)
        restartButton.setTextColor(NativeUiPalette.textPrimary)
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
