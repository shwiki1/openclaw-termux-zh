package com.agent.cyx

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding

class NativeTerminalActivity : Activity() {
    private lateinit var launchGroupId: String
    private lateinit var rootLayout: LinearLayout
    private lateinit var titleView: TextView
    private lateinit var sessionBadgeView: TextView
    private lateinit var sessionSwitcherView: TextView
    private lateinit var terminalContainer: FrameLayout
    private lateinit var baseConfig: NativeTerminalSessionConfig
    private val sessions = mutableListOf<NativeTerminalSessionConfig>()
    private var activeIndex = 0
    private var activeTerminalView: NativeTerminalSessionView? = null
    private var closedAllSessions = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val parsedConfig = parseIntentConfig(intent) ?: run {
            finish()
            return
        }
        baseConfig = parsedConfig
        launchGroupId = parsedConfig.sessionId
        val savedSessionsForGroup = savedSessions[launchGroupId]
        if (savedInstanceState == null && !savedSessionsForGroup.isNullOrEmpty()) {
            sessions.addAll(savedSessionsForGroup)
            activeIndex = (savedActiveIndexes[launchGroupId] ?: 0)
                .coerceIn(0, sessions.lastIndex)
        } else {
            sessions.add(parsedConfig)
        }

        setResult(Activity.RESULT_OK)
        TerminalSessionService.start(applicationContext)
        setContentView(createContentView())
        showSession(activeIndex, restart = baseConfig.restart)
    }

    override fun onBackPressed() {
        finish()
    }

    override fun onDestroy() {
        if (!closedAllSessions) {
            persistSessions()
        }
        activeTerminalView?.dispose(closeSession = false)
        activeTerminalView = null
        TerminalSessionService.stop(applicationContext)
        super.onDestroy()
    }

    private fun createContentView(): View {
        window.statusBarColor = NativeUiPalette.background
        window.navigationBarColor = NativeUiPalette.background
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(NativeUiPalette.background)
            clipToPadding = false
        }

        titleView = TextView(this).apply {
            setTextColor(NativeUiPalette.textPrimary)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
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
        sessionSwitcherView = createActionButton("会话") {
            showSessionMenu(it)
        }
        terminalContainer = FrameLayout(this)

        rootLayout.addView(createTitleRow())
        rootLayout.addView(createActionRow())
        rootLayout.addView(
            terminalContainer,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
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
            terminalContainer.updatePadding(
                bottom = if (imeVisible) imeBottom else systemBars.bottom,
            )
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
            setPadding(dp(8), dp(8), dp(8), dp(8))
            addView(createActionButton("返回") { finish() })
            addView(
                titleView,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = dp(10)
                    marginEnd = dp(8)
                },
            )
            addView(sessionBadgeView)
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
            addView(sessionSwitcherView)
            addView(createActionButton("新建") { openNewSession() })
            addView(createActionButton("粘贴") { activeTerminalView?.paste() })
            addView(createActionButton("重启") { activeTerminalView?.restart() })
            addView(createActionButton("关闭") { closeCurrentSession() })
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            background = nativeCardDrawable(
                fillColor = NativeUiPalette.surfaceAlt,
                strokeColor = NativeUiPalette.border,
                radiusDp = 10,
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(6)
                marginEnd = dp(6)
                topMargin = dp(6)
                bottomMargin = dp(4)
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
            minimumWidth = dp(44)
            minHeight = dp(32)
            setPadding(dp(9), dp(5), dp(9), dp(5))
            background = actionButtonDrawable(NativeUiPalette.surfaceRaised)
            setOnClickListener { onClick(it) }
        }.also { button ->
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            params.marginEnd = dp(6)
            button.layoutParams = params
        }
    }

    private fun actionButtonDrawable(color: Int) =
        nativeCardDrawable(
            fillColor = color,
            strokeColor = NativeUiPalette.borderStrong,
            radiusDp = 8,
        )

    private fun showSession(index: Int, restart: Boolean = false) {
        if (index !in sessions.indices) {
            return
        }
        activeTerminalView?.dispose(closeSession = false)
        terminalContainer.removeAllViews()

        activeIndex = index
        val targetConfig = sessions[index].copy(restart = restart, keepAlive = true, useNativeToolbar = true)
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
    }

    private fun updateChrome() {
        val activeSession = sessions.getOrNull(activeIndex) ?: return
        titleView.text = activeSession.title
        val multipleSessions = sessions.size > 1
        sessionBadgeView.visibility = if (multipleSessions) View.VISIBLE else View.GONE
        sessionBadgeView.text = "${activeIndex + 1}/${sessions.size}"
        sessionSwitcherView.visibility = if (multipleSessions) View.VISIBLE else View.GONE
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
            ),
        )
        showSession(sessions.lastIndex)
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
    }

    private fun showSessionMenu(anchor: View) {
        val popup = PopupMenu(this, anchor)
        sessions.forEachIndexed { index, session ->
            popup.menu.add(0, index, index, session.title)
        }
        popup.setOnMenuItemClickListener { item ->
            showSession(item.itemId)
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
        savedSessions[launchGroupId] = sessions.map { it.copy(restart = false) }
        savedActiveIndexes[launchGroupId] = activeIndex
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

        private val savedSessions = mutableMapOf<String, List<NativeTerminalSessionConfig>>()
        private val savedActiveIndexes = mutableMapOf<String, Int>()

        fun createIntent(context: Context, config: NativeTerminalSessionConfig): Intent {
            return Intent(context, NativeTerminalActivity::class.java).apply {
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
