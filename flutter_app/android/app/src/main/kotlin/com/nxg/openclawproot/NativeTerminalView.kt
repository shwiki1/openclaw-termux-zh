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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.roundToInt

class NativeTerminalViewFactory(
    private val messenger: BinaryMessenger,
    private val appContext: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>) ?: emptyMap<String, Any?>()
        return NativeTerminalPlatformView(context, appContext, messenger, viewId, params)
    }
}

private data class NativeTerminalSessionHolder(
    val session: TerminalSession,
    val keepAlive: Boolean,
)

class NativeTerminalPlatformView(
    context: Context,
    private val appContext: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val params: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val container = FrameLayout(context)
    private val contentContainer = LinearLayout(context)
    private val terminalView = TerminalView(context, null)
    private val bottomSpaceView = View(context)
    private val inputStripRect = Rect()
    private val containerInputStripRect = Rect()
    private val channel = MethodChannel(messenger, "com.agent.cyx/native_terminal_$viewId")
    private val sessionId = params.stringValue("sessionId") ?: "native-shell"
    private val keepAlive = params.booleanValue("keepAlive", false)
    private val useNativeToolbar = params.booleanValue("useNativeToolbar", false)
    private var fontSize = params.intValue("fontSize", 18).coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
    private var ctrlModifierActive = false
    private var altModifierActive = false
    private var ctrlButtonView: TextView? = null
    private var altButtonView: TextView? = null
    private val client = NativeTerminalClient(
        appContext,
        terminalView,
        channel,
        params.booleanValue("emitOutput", false),
        params.booleanValue("renderingPaused", false),
        fontSize,
        ::setFontSize,
        ::focusAndShowKeyboard,
    )
    private val toolbarStrip = if (useNativeToolbar) createToolbarStrip(context) else null
    private var holder: NativeTerminalSessionHolder? = null
    private var lastKeyboardShowRequestElapsedMs = 0L
    private var disposed = false
    private val keyboardRetryRunnable = Runnable {
        retryShowKeyboardIfNeeded()
    }

    init {
        container.setBackgroundColor(Color.BLACK)
        contentContainer.orientation = LinearLayout.VERTICAL
        contentContainer.setBackgroundColor(Color.BLACK)
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
        bottomSpaceView.setBackgroundColor(Color.TRANSPARENT)
        contentContainer.addView(
            bottomSpaceView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(1),
            ),
        )
        container.addView(
            contentContainer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        channel.setMethodCallHandler(this)
        val reusedSession = attachOrCreateSession(restart = params.booleanValue("restart", false))
        terminalView.post {
            if (!disposed) {
                focusAndShowKeyboard(allowRetry = !reusedSession)
            }
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        disposed = true
        terminalView.removeCallbacks(keyboardRetryRunnable)
        hideKeyboard()
        channel.setMethodCallHandler(null)
        val current = holder
        if (current != null) {
            if (current.keepAlive) {
                current.session.updateTerminalSessionClient(DetachedTerminalClient)
            } else {
                current.session.finishIfRunning()
                sessions.remove(sessionId)
            }
        }
        holder = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeBytes" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.error("INVALID_ARGS", "writeBytes requires Uint8List", null)
                } else {
                    holder?.session?.write(bytes, 0, bytes.size)
                    result.success(true)
                }
            }
            "writeText" -> {
                val text = call.argument<String>("text") ?: ""
                holder?.session?.write(text)
                result.success(true)
            }
            "paste" -> {
                val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(appContext)?.toString()
                if (!text.isNullOrEmpty()) {
                    holder?.session?.write(text)
                }
                focusAndShowKeyboard()
                result.success(true)
            }
            "showKeyboard" -> {
                focusAndShowKeyboard()
                result.success(true)
            }
            "hideKeyboard" -> {
                hideKeyboard()
                result.success(true)
            }
            "setFontSize" -> {
                val nextFontSize = (call.argument<Number>("fontSize")?.toInt() ?: fontSize)
                    .coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
                setFontSize(nextFontSize)
                result.success(nextFontSize)
            }
            "setRenderingPaused" -> {
                client.setRenderingPaused(call.argument<Boolean>("paused") == true)
                result.success(true)
            }
            "restart" -> {
                attachOrCreateSession(restart = true)
                focusAndShowKeyboard(allowRetry = true)
                result.success(true)
            }
            "close" -> {
                hideKeyboard()
                holder?.session?.finishIfRunning()
                sessions.remove(sessionId)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun attachOrCreateSession(restart: Boolean): Boolean {
        if (restart) {
            sessions.remove(sessionId)?.session?.finishIfRunning()
        }

        val existing = sessions[sessionId]
        if (existing != null && existing.session.isRunning) {
            existing.session.updateTerminalSessionClient(client)
            holder = existing
            terminalView.attachSession(existing.session)
            terminalView.updateSize()
            return true
        }

        val executable = params.stringValue("executable")
            ?: throw IllegalArgumentException("Native terminal requires executable")
        val cwd = params.stringValue("cwd") ?: "/"
        val arguments = params.stringListValue("arguments")
        val env = params.stringMapValue("environment")
            .map { (key, value) -> "$key=$value" }
            .toTypedArray()
        val argv = arrayOf(executable.substringAfterLast('/')) + arguments.toTypedArray()
        val session = TerminalSession(
            executable,
            cwd,
            argv,
            env,
            params.intValue("transcriptRows", DEFAULT_TRANSCRIPT_ROWS)
                .coerceIn(MIN_TRANSCRIPT_ROWS, MAX_TRANSCRIPT_ROWS),
            client,
        )
        session.mSessionName = sessionId
        val newHolder = NativeTerminalSessionHolder(session, keepAlive)
        holder = newHolder
        if (keepAlive) {
            sessions[sessionId] = newHolder
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

    private fun hideKeyboard() {
        terminalView.removeCallbacks(keyboardRetryRunnable)
        val imm = terminalView.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return
        imm.hideSoftInputFromWindow(terminalView.windowToken, 0)
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
        if (terminalView.hasFocus().not()) {
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
            setBackgroundColor(Color.BLACK)
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dpToPx(4), dpToPx(4), dpToPx(4), dpToPx(4))
            gravity = Gravity.CENTER_VERTICAL
        }
        scrollView.setOnApplyWindowInsetsListener { _, insets ->
            row.setPadding(
                dpToPx(4),
                dpToPx(4),
                dpToPx(4),
                dpToPx(4) + insets.systemWindowInsetBottom,
            )
            insets
        }
        scrollView.addView(
            row,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        scrollView.requestApplyInsets()

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
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.MONOSPACE
            minimumWidth = dpToPx(36)
            minimumHeight = dpToPx(34)
            setPadding(dpToPx(6), dpToPx(4), dpToPx(6), dpToPx(4))
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
                marginStart = dpToPx(2)
                marginEnd = dpToPx(2)
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
                toolbarButtonDrawable(TOOLBAR_ACTIVE_PRESSED_COLOR),
            )
            addState(
                intArrayOf(android.R.attr.state_pressed),
                toolbarButtonDrawable(TOOLBAR_BUTTON_PRESSED_COLOR),
            )
            addState(
                intArrayOf(android.R.attr.state_selected),
                toolbarButtonDrawable(TOOLBAR_ACTIVE_COLOR),
            )
            addState(intArrayOf(), toolbarButtonDrawable(TOOLBAR_BUTTON_COLOR))
        }
    }

    private fun toolbarButtonDrawable(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            cornerRadius = dpToPx(6).toFloat()
            setColor(color)
        }
    }

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
        val density = container.resources.displayMetrics.density
        val minimumStripHeight = (72f * density).roundToInt()
        val estimatedPromptRowsHeight = (fontSize * 5.0f).roundToInt()
        return maxOf(minimumStripHeight, estimatedPromptRowsHeight)
    }

    private fun dpToPx(dp: Int): Int =
        (dp * container.resources.displayMetrics.density).roundToInt()

    private fun requestInputStripVisible() {
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
        containerInputStripRect.set(inputStripRect)
        contentContainer.offsetDescendantRectToMyCoords(terminalView, containerInputStripRect)
        if (useNativeToolbar) {
            val contentBottom = (contentContainer.height - contentContainer.paddingBottom)
                .coerceAtLeast(containerInputStripRect.bottom)
            containerInputStripRect.bottom = contentBottom
        }
        container.requestRectangleOnScreen(containerInputStripRect, true)
    }

    companion object {
        private const val MIN_FONT_SIZE = 12
        private const val MAX_FONT_SIZE = 32
        private const val MIN_TRANSCRIPT_ROWS = 400
        private const val MAX_TRANSCRIPT_ROWS = 3000
        private const val DEFAULT_TRANSCRIPT_ROWS = 3000
        private const val TOOLBAR_BUTTON_COLOR = 0xFF161616.toInt()
        private const val TOOLBAR_BUTTON_PRESSED_COLOR = 0xFF2B2B2B.toInt()
        private const val TOOLBAR_ACTIVE_COLOR = 0xFF00C853.toInt()
        private const val TOOLBAR_ACTIVE_PRESSED_COLOR = 0xFF009B3F.toInt()
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
    private val channel: MethodChannel,
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
                channel.invokeMethod("onOutput", delta)
            }
        }
    }

    override fun onTitleChanged(changedSession: TerminalSession) {
        channel.invokeMethod("onTitleChanged", changedSession.title ?: "")
    }

    override fun onSessionFinished(finishedSession: TerminalSession) {
        requestScreenUpdate(immediate = true)
        channel.invokeMethod("onSessionFinished", finishedSession.exitStatus)
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

private fun Map<*, *>.stringValue(key: String): String? = this[key] as? String

private fun Map<*, *>.booleanValue(key: String, defaultValue: Boolean): Boolean =
    this[key] as? Boolean ?: defaultValue

private fun Map<*, *>.intValue(key: String, defaultValue: Int): Int =
    (this[key] as? Number)?.toInt() ?: defaultValue

private fun Map<*, *>.stringListValue(key: String): List<String> =
    (this[key] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()

private fun Map<*, *>.stringMapValue(key: String): Map<String, String> =
    (this[key] as? Map<*, *>)
        ?.mapNotNull { (key, value) ->
            val stringKey = key as? String
            val stringValue = value as? String
            if (stringKey != null && stringValue != null) stringKey to stringValue else null
        }
        ?.toMap()
        ?: emptyMap()
