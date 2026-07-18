package com.agent.cyx

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import com.termux.terminal.TerminalEmulator
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalView
import com.termux.view.TerminalViewClient
import kotlin.math.abs
import kotlin.math.roundToInt

data class NativeTerminalSessionConfig(
    val sessionId: String,
    val title: String = "Terminal",
    val executable: String,
    val cwd: String = "/",
    val arguments: List<String> = emptyList(),
    val environment: Map<String, String> = emptyMap(),
    val restart: Boolean = false,
    val keepAlive: Boolean = false,
    val emitOutput: Boolean = false,
    val renderingPaused: Boolean = false,
    val useNativeToolbar: Boolean = false,
    val useCodexChrome: Boolean = false,
    val transcriptRows: Int = 3000,
    val fontSize: Int = 18,
)

interface NativeTerminalSessionCallbacks {
    fun onOutput(output: String) = Unit
    fun onTitleChanged(title: String) = Unit
    fun onSessionFinished(exitStatus: Int) = Unit
}

private data class NativeTerminalSessionHolder(
    val session: TerminalSession,
    val keepAlive: Boolean,
)

class NativeTerminalSessionView(
    context: Context,
    private val appContext: Context,
    val config: NativeTerminalSessionConfig,
    private val callbacks: NativeTerminalSessionCallbacks,
) : FrameLayout(context) {
    private val contentContainer = LinearLayout(context)
    private val terminalView = TerminalView(context, null)
    private val inputStripRect = Rect()
    private val parentInputStripRect = Rect()
    private var fontSize = config.fontSize.coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
    private var ctrlModifierActive = false
    private var altModifierActive = false
    private var ctrlButtonView: TextView? = null
    private var altButtonView: TextView? = null
    private val client = NativeTerminalClient(
        context = appContext,
        terminalView = terminalView,
        callbacks = callbacks,
        emitOutput = config.emitOutput,
        renderingPaused = config.renderingPaused,
        fontSize = fontSize,
        setFontSize = ::setFontSize,
        showKeyboard = ::focusAndShowKeyboard,
    )
    private val toolbarStrip = if (config.useNativeToolbar) createToolbarStrip(context) else null
    private var holder: NativeTerminalSessionHolder? = null
    private var lastKeyboardShowRequestElapsedMs = 0L
    private var disposed = false
    private val keyboardRetryRunnable = Runnable {
        retryShowKeyboardIfNeeded()
    }

    init {
        setBackgroundColor(NativeUiPalette.background)
        contentContainer.orientation = LinearLayout.VERTICAL
        contentContainer.setBackgroundColor(NativeUiPalette.background)
        terminalView.setTerminalViewClient(client)
        terminalView.setTextSize(fontSize)
        terminalView.setTypeface(Typeface.MONOSPACE)
        terminalView.isFocusable = true
        terminalView.isFocusableInTouchMode = true
        terminalView.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                requestInputStripVisible()
            }
        }
        contentContainer.addView(
            terminalView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        toolbarStrip?.let { toolbar ->
            contentContainer.addView(
                toolbar,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        addView(
            contentContainer,
            LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
            ),
        )

        val reusedSession = attachOrCreateSession(restart = config.restart)
        terminalView.post {
            if (!disposed) {
                focusAndShowKeyboard(allowRetry = !reusedSession)
            }
        }
    }

    fun writeBytes(bytes: ByteArray) {
        holder?.session?.write(bytes, 0, bytes.size)
    }

    fun writeText(text: String) {
        holder?.session?.write(text)
    }

    fun paste() {
        val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(appContext)?.toString()
        if (!text.isNullOrEmpty()) {
            holder?.session?.write(text)
        }
        focusAndShowKeyboard()
    }

    fun showKeyboard() {
        focusAndShowKeyboard()
    }

    fun requestToolbarVisible() {
        if (!config.useNativeToolbar) {
            requestInputStripVisible()
        }
    }

    fun hideKeyboard() {
        terminalView.removeCallbacks(keyboardRetryRunnable)
        val imm = terminalView.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return
        imm.hideSoftInputFromWindow(terminalView.windowToken, 0)
    }

    fun setRenderingPaused(paused: Boolean) {
        client.setRenderingPaused(paused)
    }

    fun applyFontSize(nextFontSize: Int) {
        setFontSize(nextFontSize)
    }

    fun restart() {
        attachOrCreateSession(restart = true)
        focusAndShowKeyboard(allowRetry = true)
    }

    fun closeSession() {
        if (disposed) {
            return
        }
        hideKeyboard()
        holder?.session?.finishIfRunning()
        sessions.remove(config.sessionId)
    }

    fun dispose(closeSession: Boolean = false) {
        if (disposed) {
            return
        }
        disposed = true
        terminalView.removeCallbacks(keyboardRetryRunnable)
        hideKeyboard()
        val current = holder
        if (current != null) {
            if (closeSession || !current.keepAlive) {
                current.session.finishIfRunning()
                sessions.remove(config.sessionId)
            } else {
                current.session.updateTerminalSessionClient(DetachedTerminalClient)
            }
        }
        holder = null
    }

    private fun attachOrCreateSession(restart: Boolean): Boolean {
        if (restart) {
            sessions.remove(config.sessionId)?.session?.finishIfRunning()
        }

        val existing = sessions[config.sessionId]
        if (existing != null && existing.session.isRunning) {
            existing.session.updateTerminalSessionClient(client)
            holder = existing
            terminalView.attachSession(existing.session)
            terminalView.updateSize()
            return true
        }

        val env = config.environment
            .map { (key, value) -> "$key=$value" }
            .toTypedArray()
        val argv = arrayOf(config.executable.substringAfterLast('/')) + config.arguments.toTypedArray()
        val session = TerminalSession(
            config.executable,
            config.cwd,
            argv,
            env,
            config.transcriptRows.coerceIn(MIN_TRANSCRIPT_ROWS, MAX_TRANSCRIPT_ROWS),
            client,
        )
        session.mSessionName = config.sessionId
        val newHolder = NativeTerminalSessionHolder(session, config.keepAlive)
        holder = newHolder
        if (config.keepAlive) {
            sessions[config.sessionId] = newHolder
        }
        terminalView.attachSession(session)
        terminalView.updateSize()
        return false
    }

    private fun focusAndShowKeyboard(allowRetry: Boolean = false) {
        if (disposed) {
            return
        }
        if (!terminalView.hasFocus()) {
            terminalView.requestFocus()
        }
        requestInputStripVisible()
        requestKeyboardShow()
        terminalView.removeCallbacks(keyboardRetryRunnable)
        if (allowRetry) {
            terminalView.postDelayed(keyboardRetryRunnable, 160)
        }
    }

    private fun requestKeyboardShow(force: Boolean = false) {
        val imm = terminalView.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return
        val now = SystemClock.uptimeMillis()
        val recentlyRequested = now - lastKeyboardShowRequestElapsedMs < 120L
        if (!force && recentlyRequested && imm.isActive(terminalView)) {
            return
        }
        imm.showSoftInput(terminalView, InputMethodManager.SHOW_IMPLICIT)
        lastKeyboardShowRequestElapsedMs = now
    }

    private fun retryShowKeyboardIfNeeded() {
        if (disposed) {
            return
        }
        requestInputStripVisible()
        val imm = terminalView.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return
        if (!terminalView.hasFocus()) {
            terminalView.requestFocus()
        }
        if (!imm.isActive(terminalView)) {
            requestKeyboardShow(force = true)
        }
    }

    private fun setFontSize(nextFontSize: Int) {
        val clamped = nextFontSize.coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
        if (clamped == fontSize) return
        fontSize = clamped
        client.fontSize = clamped
        terminalView.setTextSize(clamped)
        terminalView.updateSize()
    }

    private fun createToolbarStrip(context: Context): HorizontalScrollView {
        val scrollView = HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            if (config.useCodexChrome) {
                setBackgroundColor(NativeUiPalette.background)
            } else {
                setBackgroundColor(Color.BLACK)
            }
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            val rowPadding = if (config.useCodexChrome) 4 else 2
            setPadding(
                dpToPx(rowPadding),
                dpToPx(rowPadding),
                dpToPx(rowPadding),
                dpToPx(rowPadding),
            )
            gravity = Gravity.CENTER_VERTICAL
        }
        scrollView.addView(
            row,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        addToolbarButton(row, "ESC") {
            sendToolbarInput("\u001b")
        }
        ctrlButtonView = addToolbarButton(row, "CTRL") {
            toggleCtrlModifier()
        }
        altButtonView = addToolbarButton(row, "ALT") {
            toggleAltModifier()
        }
        addToolbarButton(row, "TAB") {
            sendToolbarInput("\t")
        }
        addToolbarButton(row, "ENTER") {
            sendToolbarInput("\r")
        }
        addToolbarSpacer(row)
        addToolbarButton(row, "UP") {
            sendToolbarInput("\u001b[A")
        }
        addToolbarButton(row, "DN") {
            sendToolbarInput("\u001b[B")
        }
        addToolbarButton(row, "LT") {
            sendToolbarInput("\u001b[D")
        }
        addToolbarButton(row, "RT") {
            sendToolbarInput("\u001b[C")
        }
        addToolbarSpacer(row)
        addToolbarButton(row, "HOME") {
            sendToolbarInput("\u001b[H")
        }
        addToolbarButton(row, "END") {
            sendToolbarInput("\u001b[F")
        }
        addToolbarButton(row, "PGUP") {
            sendToolbarInput("\u001b[5~")
        }
        addToolbarButton(row, "PGDN") {
            sendToolbarInput("\u001b[6~")
        }
        addToolbarSpacer(row)
        addToolbarButton(row, "-") {
            sendToolbarInput("-")
        }
        addToolbarButton(row, "/") {
            sendToolbarInput("/")
        }
        addToolbarButton(row, "|") {
            sendToolbarInput("|")
        }
        addToolbarButton(row, "~") {
            sendToolbarInput("~")
        }
        addToolbarButton(row, "_") {
            sendToolbarInput("_")
        }
        updateModifierButtons()
        return scrollView
    }

    private fun addToolbarButton(
        row: LinearLayout,
        label: String,
        onClick: () -> Unit,
    ): TextView {
        val button = TextView(row.context).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(NativeUiPalette.textPrimary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.MONOSPACE
            minimumWidth = dpToPx(if (config.useCodexChrome) 38 else 36)
            minimumHeight = dpToPx(if (config.useCodexChrome) 34 else 32)
            setPadding(
                dpToPx(if (config.useCodexChrome) 8 else 6),
                dpToPx(if (config.useCodexChrome) 5 else 4),
                dpToPx(if (config.useCodexChrome) 8 else 6),
                dpToPx(if (config.useCodexChrome) 5 else 4),
            )
            isClickable = true
            isFocusable = false
            isFocusableInTouchMode = false
            isHapticFeedbackEnabled = true
            background = toolbarButtonBackground()
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onClick()
            }
        }
        row.addView(
            button,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dpToPx(if (config.useCodexChrome) 2 else 1)
                marginEnd = dpToPx(if (config.useCodexChrome) 2 else 1)
            },
        )
        return button
    }

    private fun addToolbarSpacer(row: LinearLayout) {
        row.addView(
            View(row.context),
            LinearLayout.LayoutParams(dpToPx(4), 1),
        )
    }

    private fun toolbarButtonBackground(): StateListDrawable {
        return StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_selected, android.R.attr.state_pressed),
                toolbarButtonDrawable(toolbarActivePressedColor()),
            )
            addState(
                intArrayOf(android.R.attr.state_pressed),
                toolbarButtonDrawable(toolbarButtonPressedColor()),
            )
            addState(
                intArrayOf(android.R.attr.state_selected),
                toolbarButtonDrawable(toolbarActiveColor()),
            )
            addState(intArrayOf(), toolbarButtonDrawable(toolbarButtonColor()))
        }
    }

    private fun toolbarButtonDrawable(color: Int): GradientDrawable {
        return if (config.useCodexChrome) {
            GradientDrawable().apply {
                setColor(color)
            }
        } else {
            GradientDrawable().apply {
                cornerRadius = dpToPx(6).toFloat()
                setColor(color)
            }
        }
    }

    private fun toolbarButtonColor(): Int =
        if (config.useCodexChrome) NativeUiPalette.surfaceRaised else 0xFF161616.toInt()

    private fun toolbarButtonPressedColor(): Int =
        if (config.useCodexChrome) NativeUiPalette.surface else 0xFF2B2B2B.toInt()

    private fun toolbarActiveColor(): Int =
        if (config.useCodexChrome) NativeUiPalette.accentSoft else 0xFF00C853.toInt()

    private fun toolbarActivePressedColor(): Int =
        if (config.useCodexChrome) NativeUiPalette.accentPressed else 0xFF009B3F.toInt()

    private fun updateModifierButtons() {
        ctrlButtonView?.isSelected = ctrlModifierActive
        altButtonView?.isSelected = altModifierActive
    }

    private fun toggleCtrlModifier() {
        ctrlModifierActive = !ctrlModifierActive
        if (ctrlModifierActive) {
            altModifierActive = false
        }
        updateModifierButtons()
        focusAndShowKeyboard()
    }

    private fun toggleAltModifier() {
        altModifierActive = !altModifierActive
        if (altModifierActive) {
            ctrlModifierActive = false
        }
        updateModifierButtons()
        focusAndShowKeyboard()
    }

    private fun sendToolbarInput(data: String) {
        val session = holder?.session ?: run {
            focusAndShowKeyboard()
            return
        }

        if (ctrlModifierActive) {
            ctrlModifierActive = false
            updateModifierButtons()
            if (data.length == 1) {
                val code = data.lowercase()[0].code
                if (code in 97..122) {
                    val value = byteArrayOf((code - 96).toByte())
                    session.write(value, 0, value.size)
                    focusAndShowKeyboard()
                    return
                }
            }
            session.write(CTRL_SEQUENCE_MAP[data] ?: data)
            focusAndShowKeyboard()
            return
        }

        if (altModifierActive) {
            altModifierActive = false
            updateModifierButtons()
            session.write("\u001b$data")
            focusAndShowKeyboard()
            return
        }

        session.write(data)
        focusAndShowKeyboard()
    }

    private fun visibleInputStripHeightPx(): Int {
        val density = resources.displayMetrics.density
        val minimumStripHeight = (72f * density).roundToInt()
        val estimatedPromptRowsHeight = (fontSize * 5.0f).roundToInt()
        return maxOf(minimumStripHeight, estimatedPromptRowsHeight)
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).roundToInt()

    private fun requestInputStripVisible() {
        val toolbar = toolbarStrip
        if (config.useNativeToolbar && toolbar != null) {
            return
        }
        if (terminalView.width <= 0 || terminalView.height <= 0) {
            return
        }
        val stripHeight = visibleInputStripHeightPx().coerceAtLeast(1)
        inputStripRect.set(
            0,
            (terminalView.height - stripHeight).coerceAtLeast(0),
            terminalView.width,
            terminalView.height,
        )
        terminalView.requestRectangleOnScreen(inputStripRect, true)
        parentInputStripRect.set(inputStripRect)
        contentContainer.offsetDescendantRectToMyCoords(terminalView, parentInputStripRect)
        requestRectangleOnScreen(parentInputStripRect, true)
    }

    companion object {
        private const val MIN_FONT_SIZE = 12
        private const val MAX_FONT_SIZE = 32
        private const val MIN_TRANSCRIPT_ROWS = 400
        private const val MAX_TRANSCRIPT_ROWS = 3000
        private val CTRL_SEQUENCE_MAP = mapOf(
            "\u001b[A" to "\u001b[1;5A",
            "\u001b[B" to "\u001b[1;5B",
            "\u001b[D" to "\u001b[1;5D",
            "\u001b[C" to "\u001b[1;5C",
            "\u001b[H" to "\u001b[1;5H",
            "\u001b[F" to "\u001b[1;5F",
            "\u001b[5~" to "\u001b[5;5~",
            "\u001b[6~" to "\u001b[6;5~",
        )
        private val sessions = mutableMapOf<String, NativeTerminalSessionHolder>()
    }
}

private object DetachedTerminalClient : TerminalSessionClient {
    override fun onTextChanged(changedSession: TerminalSession) = Unit
    override fun onTitleChanged(changedSession: TerminalSession) = Unit
    override fun onSessionFinished(finishedSession: TerminalSession) = Unit
    override fun onCopyTextToClipboard(session: TerminalSession, text: String) = Unit
    override fun onPasteTextFromClipboard(session: TerminalSession) = Unit
    override fun onBell(session: TerminalSession) = Unit
    override fun onColorsChanged(session: TerminalSession) = Unit
    override fun onTerminalCursorStateChange(state: Boolean) = Unit
    override fun getTerminalCursorStyle(): Int = TerminalEmulator.DEFAULT_TERMINAL_CURSOR_STYLE
    override fun logError(tag: String, message: String) {
        android.util.Log.e(tag, message)
    }
    override fun logWarn(tag: String, message: String) {
        android.util.Log.w(tag, message)
    }
    override fun logInfo(tag: String, message: String) {
        android.util.Log.i(tag, message)
    }
    override fun logDebug(tag: String, message: String) {
        android.util.Log.d(tag, message)
    }
    override fun logVerbose(tag: String, message: String) {
        android.util.Log.v(tag, message)
    }
    override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) {
        android.util.Log.e(tag, message, e)
    }
    override fun logStackTrace(tag: String, e: Exception) {
        android.util.Log.e(tag, "Detached native terminal error", e)
    }
}

private class NativeTerminalClient(
    private val context: Context,
    private val terminalView: TerminalView,
    private val callbacks: NativeTerminalSessionCallbacks,
    private val emitOutput: Boolean,
    private var renderingPaused: Boolean,
    var fontSize: Int,
    private val setFontSize: (Int) -> Unit,
    private val showKeyboard: () -> Unit,
) : TerminalSessionClient, TerminalViewClient {
    private var refreshScheduled = false
    private var refreshPending = false
    private var lastRefreshMs = 0L
    private var controlDown = false
    private var altDown = false
    private var lastTranscript = ""
    private var pendingScale = 1.0f
    private var lastScaleApplyMs = 0L

    override fun onTextChanged(changedSession: TerminalSession) {
        requestScreenUpdate()
        if (emitOutput) {
            val transcript = changedSession.emulator?.screen?.getTranscriptTextWithFullLinesJoined() ?: ""
            val delta = if (transcript.startsWith(lastTranscript)) {
                transcript.substring(lastTranscript.length)
            } else {
                transcript
            }
            lastTranscript = transcript
            if (delta.isNotEmpty()) {
                terminalView.post {
                    callbacks.onOutput(delta)
                }
            }
        }
    }

    override fun onTitleChanged(changedSession: TerminalSession) {
        val title = changedSession.title ?: ""
        terminalView.post {
            callbacks.onTitleChanged(title)
        }
    }

    override fun onSessionFinished(finishedSession: TerminalSession) {
        requestScreenUpdate(immediate = true)
        val exitStatus = finishedSession.exitStatus
        terminalView.post {
            callbacks.onSessionFinished(exitStatus)
        }
    }

    override fun onCopyTextToClipboard(session: TerminalSession, text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("terminal", text))
    }

    override fun onPasteTextFromClipboard(session: TerminalSession) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString()
        if (!text.isNullOrEmpty()) {
            session.write(text)
        }
    }

    override fun onBell(session: TerminalSession) = Unit

    override fun onColorsChanged(session: TerminalSession) {
        requestScreenUpdate(immediate = true)
    }

    override fun onTerminalCursorStateChange(state: Boolean) {
        terminalView.setTerminalCursorBlinkerState(state, true)
    }

    override fun getTerminalCursorStyle(): Int = TerminalEmulator.DEFAULT_TERMINAL_CURSOR_STYLE

    override fun onScale(scale: Float): Float {
        if (scale.isNaN() || scale.isInfinite()) return 1.0f
        pendingScale *= scale.coerceIn(0.85f, 1.15f)
        val nextFontSize = (fontSize * pendingScale).roundToInt().coerceIn(12, 32)
        val now = SystemClock.uptimeMillis()
        val crossedScaleThreshold = pendingScale <= 0.92f || pendingScale >= 1.08f
        val canApply = now - lastScaleApplyMs >= 40L || crossedScaleThreshold
        if (abs(nextFontSize - fontSize) >= 1 && canApply) {
            setFontSize(nextFontSize)
            pendingScale = 1.0f
            lastScaleApplyMs = now
        } else if (nextFontSize == fontSize &&
            crossedScaleThreshold &&
            (fontSize == 12 || fontSize == 32)
        ) {
            pendingScale = 1.0f
            lastScaleApplyMs = now
        }
        return 1.0f
    }

    override fun onSingleTapUp(e: MotionEvent) {
        showKeyboard()
    }

    fun setRenderingPaused(paused: Boolean) {
        if (renderingPaused == paused) return
        renderingPaused = paused
        if (!paused && (refreshPending || refreshScheduled)) {
            refreshPending = false
            refreshScheduled = false
            terminalView.post {
                requestScreenUpdate(immediate = true)
            }
        }
    }

    private fun requestScreenUpdate(immediate: Boolean = false) {
        if (renderingPaused) {
            refreshPending = true
            return
        }
        val now = SystemClock.uptimeMillis()
        val elapsed = now - lastRefreshMs
        if (immediate || elapsed >= MIN_REFRESH_INTERVAL_MS) {
            refreshPending = false
            refreshScheduled = false
            lastRefreshMs = now
            terminalView.onScreenUpdated()
            return
        }
        refreshPending = true
        if (refreshScheduled) {
            return
        }
        refreshScheduled = true
        terminalView.postDelayed({
            refreshScheduled = false
            if (renderingPaused) {
                refreshPending = true
                return@postDelayed
            }
            if (!refreshPending) {
                return@postDelayed
            }
            refreshPending = false
            lastRefreshMs = SystemClock.uptimeMillis()
            terminalView.onScreenUpdated()
        }, (MIN_REFRESH_INTERVAL_MS - elapsed).coerceAtLeast(1L))
    }

    override fun shouldBackButtonBeMappedToEscape(): Boolean = false

    override fun shouldEnforceCharBasedInput(): Boolean = false

    override fun shouldUseCtrlSpaceWorkaround(): Boolean = true

    override fun isTerminalViewSelected(): Boolean = terminalView.hasFocus()

    override fun copyModeChanged(copyMode: Boolean) = Unit

    override fun onKeyDown(keyCode: Int, e: KeyEvent, session: TerminalSession): Boolean = false

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean = false

    override fun onLongPress(event: MotionEvent): Boolean = false

    override fun readControlKey(): Boolean {
        val value = controlDown
        controlDown = false
        return value
    }

    override fun readAltKey(): Boolean {
        val value = altDown
        altDown = false
        return value
    }

    override fun readShiftKey(): Boolean = false

    override fun readFnKey(): Boolean = false

    override fun onCodePoint(codePoint: Int, ctrlDown: Boolean, session: TerminalSession): Boolean = false

    override fun onEmulatorSet() {
        terminalView.setTerminalCursorBlinkerRate(700)
        terminalView.setTerminalCursorBlinkerState(true, true)
    }

    override fun logError(tag: String, message: String) {
        android.util.Log.e(tag, message)
    }
    override fun logWarn(tag: String, message: String) {
        android.util.Log.w(tag, message)
    }
    override fun logInfo(tag: String, message: String) {
        android.util.Log.i(tag, message)
    }
    override fun logDebug(tag: String, message: String) {
        android.util.Log.d(tag, message)
    }
    override fun logVerbose(tag: String, message: String) {
        android.util.Log.v(tag, message)
    }
    override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) {
        android.util.Log.e(tag, message, e)
    }
    override fun logStackTrace(tag: String, e: Exception) {
        android.util.Log.e(tag, "Native terminal error", e)
    }

    companion object {
        private const val MIN_REFRESH_INTERVAL_MS = 32L
    }
}
