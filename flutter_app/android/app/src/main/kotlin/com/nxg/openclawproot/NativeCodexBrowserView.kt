package com.agent.cyx

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import kotlin.math.abs

interface NativeBrowserAutomationController {
    fun executeAction(
        action: String,
        payload: Map<String, Any?>,
        callback: (Map<String, Any?>) -> Unit,
    )
}

object NativeBrowserAutomationRegistry {
    @Volatile
    var controller: NativeBrowserAutomationController? = null
}

private enum class NativeBrowserUserAgentMode(
    val value: String,
    val label: String,
    val userAgent: String,
) {
    DESKTOP(
        value = "desktop",
        label = "电脑",
        userAgent =
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    ),
    MOBILE(
        value = "mobile",
        label = "手机",
        userAgent =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    );

    companion object {
        fun parse(raw: String?): NativeBrowserUserAgentMode? {
            val normalized = raw?.trim()?.lowercase().orEmpty()
            return when (normalized) {
                "desktop", "pc", "computer", "电脑" -> DESKTOP
                "mobile", "phone", "android", "手机", "移动" -> MOBILE
                else -> null
            }
        }
    }
}

private data class NativeBrowserTab(
    val id: Int,
    val webView: WebView,
    var userAgentMode: NativeBrowserUserAgentMode,
    var title: String = "Browser",
    var currentUrl: String = "",
    var error: String = "",
    var loading: Boolean = true,
    var canGoBack: Boolean = false,
    var canGoForward: Boolean = false,
    val navigationCallbacks: MutableList<() -> Unit> = mutableListOf(),
)

private data class NativeBrowserUiActionEntry(
    val action: String,
    val message: String,
    val ok: Boolean,
)

private data class NativeBrowserStoredScriptStep(
    val action: String,
    val payload: Map<String, Any?>,
    val note: String,
)

private data class NativeBrowserStoredScript(
    val id: String,
    val fileName: String,
    val description: String,
    val steps: List<NativeBrowserStoredScriptStep>,
    val variables: List<String>,
    val sourceUrl: String,
    val sourceTitle: String,
    val updatedAt: String,
    val lastRunAt: String,
    val runCount: Int,
) {
    val quickCommand: String
        get() = "/root/.openclaw/bin/browser-script run '${id.replace("'", "'\"'\"'")}'"
}

private data class NativeBrowserStoredUserScript(
    val id: String,
    val name: String,
    val description: String,
    val code: String,
    val matches: List<String>,
    val updatedAt: String,
)

private enum class NativeBrowserInspectorMode {
    INTERACTABLES,
    LINKS,
}

@SuppressLint("SetJavaScriptEnabled")
class NativeCodexBrowserView(
    context: Context,
) : FrameLayout(context), NativeBrowserAutomationController {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tabs = mutableListOf<NativeBrowserTab>()
    private val rootLayout = LinearLayout(context)
    private val statusColumn = LinearLayout(context)
    private val tabStrip = LinearLayout(context)
    private val recentActionsColumn = LinearLayout(context)
    private val inspectorColumn = LinearLayout(context)
    private val inspectorItemsColumn = LinearLayout(context)
    private val webViewContainer = FrameLayout(context)
    private val addressInput = EditText(context)
    private val bridgeStatusView = TextView(context)
    private val bridgeMetaView = TextView(context)
    private val uaButton = TextView(context)
    private val backButton = FrameLayout(context)
    private val forwardButton = FrameLayout(context)
    private val reloadButton = FrameLayout(context)
    private val moreButton = FrameLayout(context)
    private val newTabButton = FrameLayout(context)
    private val inspectorToggleButton = TextView(context)
    private val inspectorElementsButton = TextView(context)
    private val inspectorLinksButton = TextView(context)
    private val inspectorErrorView = TextView(context)
    private val inspectorLoadingView = TextView(context)
    private var nextTabId = 1
    private var activeTabIndex = 0
    private val recentActions = ArrayDeque<NativeBrowserUiActionEntry>()
    private var showRecentActions = false
    private var showInspector = false
    private var inspectorLoading = false
    private var inspectorMode = NativeBrowserInspectorMode.INTERACTABLES
    private var inspectorError = ""
    private var inspectorItems = emptyList<Map<String, Any?>>()

    init {
        setBackgroundColor(Color.BLACK)
        setupLayout()
        val tab = createTab()
        tabs += tab
        attachActiveTab()
        loadWelcomePage(tab)
    }

    fun dispose() {
        if (NativeBrowserAutomationRegistry.controller === this) {
            NativeBrowserAutomationRegistry.controller = null
        }
        tabs.forEach { tab ->
            tab.navigationCallbacks.clear()
            tab.webView.stopLoading()
            tab.webView.destroy()
        }
        tabs.clear()
    }

    fun handleBackPressed(): Boolean {
        val tab = activeTabOrNull() ?: return false
        if (tab.webView.canGoBack()) {
            tab.webView.goBack()
            return true
        }
        return false
    }

    override fun executeAction(
        action: String,
        payload: Map<String, Any?>,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        mainHandler.post {
            val trackedCallback: (Map<String, Any?>) -> Unit = { result ->
                recordAction(action, result)
                callback(result)
                syncChrome()
            }
            when (action) {
                "get_state" -> trackedCallback(snapshot(message = "Browser state loaded."))
                "self_test" -> runSelfTest(trackedCallback)
                "health_check" -> runHealthCheck(
                    quietWindowMs = payload.intValue("quietWindowMs", 500),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = trackedCallback,
                )
                "open" -> openUrl(payload.stringValue("url"), trackedCallback)
                "back" -> goBack(trackedCallback)
                "forward" -> goForward(trackedCallback)
                "reload" -> reloadPage(trackedCallback)
                "tab_list" -> trackedCallback(snapshot(message = "Browser tabs loaded."))
                "tab_new" -> openNewTab(payload.nullableStringValue("url"), trackedCallback)
                "tab_switch" -> switchTab(payload.intValue("id", 0), trackedCallback)
                "tab_close" -> closeTab(payload.nullableIntValue("id"), trackedCallback)
                "set_ua" -> setUserAgent(payload.stringValue("mode"), trackedCallback)
                "click" -> click(payload.stringValue("selector"), trackedCallback)
                "type" -> typeText(
                    selector = payload.stringValue("selector"),
                    text = payload.stringValue("text"),
                    submit = payload.booleanValue("submit"),
                    callback = trackedCallback,
                )
                "paste" -> pasteText(
                    selector = payload.stringValue("selector"),
                    text = payload.stringValue("text"),
                    submit = payload.booleanValue("submit"),
                    callback = trackedCallback,
                )
                "wait_for_resource" -> waitForResource(
                    pattern = payload.stringValue("pattern"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = trackedCallback,
                )
                "list_overlays" -> listOverlays(
                    maxItems = payload.intValue("maxItems", 24),
                    callback = trackedCallback,
                )
                "click_at" -> clickAt(
                    x = payload.doubleValue("x"),
                    y = payload.doubleValue("y"),
                    callback = trackedCallback,
                )
                "reset_tab" -> resetTab(payload.nullableStringValue("url"), trackedCallback)
                "wait_for_text" -> waitForText(
                    text = payload.stringValue("text"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = trackedCallback,
                )
                "wait_for_selector" -> waitForSelector(
                    selector = payload.stringValue("selector"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    visible = payload.booleanValue("visible", true),
                    callback = trackedCallback,
                )
                "scroll" -> scrollPage(
                    selector = payload.nullableStringValue("selector"),
                    direction = payload.stringValue("direction", "down"),
                    pixels = payload.intValue("pixels", 700),
                    callback = trackedCallback,
                )
                "press_key" -> pressKey(
                    selector = payload.nullableStringValue("selector"),
                    key = payload.stringValue("key"),
                    callback = trackedCallback,
                )
                "select_option" -> selectOption(
                    selector = payload.stringValue("selector"),
                    value = payload.nullableStringValue("value"),
                    label = payload.nullableStringValue("label"),
                    index = payload.nullableIntValue("index"),
                    callback = trackedCallback,
                )
                "extract" -> extract(
                    selector = payload.nullableStringValue("selector"),
                    prompt = payload.nullableStringValue("prompt"),
                    maxLength = payload.intValue("maxLength", 4000),
                    callback = trackedCallback,
                )
                "list_links" -> listLinks(
                    filter = payload.nullableStringValue("filter"),
                    maxItems = payload.intValue("maxItems", 12),
                    callback = trackedCallback,
                )
                "list_interactables" -> listInteractables(
                    filter = payload.nullableStringValue("filter"),
                    maxItems = payload.intValue("maxItems", 16),
                    callback = trackedCallback,
                )
                "highlight" -> highlight(payload.stringValue("selector"), trackedCallback)
                "capture_snapshot" -> captureSnapshot(
                    selector = payload.nullableStringValue("selector"),
                    maxLength = payload.intValue("maxLength", 8000),
                    callback = trackedCallback,
                )
                "eval" -> eval(payload.stringValue("script"), trackedCallback)
                else -> trackedCallback(
                    snapshot(
                        ok = false,
                        message = "Unsupported native browser action: $action",
                    ),
                )
            }
        }
    }

    private fun setupLayout() {
        rootLayout.apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(NativeUiPalette.background)
            clipToPadding = false
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }

        statusColumn.apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = actionButtonDrawable(
                NativeUiPalette.surface,
                strokeColor = NativeUiPalette.borderStrong,
            )
        }
        bridgeStatusView.apply {
            setTextColor(NativeUiPalette.textPrimary)
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            text = "浏览器自动化已连接"
        }
        bridgeMetaView.apply {
            setTextColor(NativeUiPalette.textMuted)
            textSize = 11f
            typeface = Typeface.MONOSPACE
            maxLines = 1
            text = "Codex 浏览器原生页"
            setPadding(0, dp(3), 0, 0)
        }
        statusColumn.addView(bridgeStatusView)
        statusColumn.addView(bridgeMetaView)

        val tabScroller = HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            background = actionButtonDrawable(
                NativeUiPalette.surfaceAlt,
                strokeColor = NativeUiPalette.border,
            )
            addView(
                tabStrip.apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(8), dp(8), dp(8), dp(8))
                },
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(10)
            }
        }

        val navRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = actionButtonDrawable(
                NativeUiPalette.surface,
                strokeColor = NativeUiPalette.border,
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(10)
            }
        }
        configureIconButton(backButton, R.drawable.lucide_chevron_left, "后退") {
            executeAction("back", emptyMap()) {}
        }
        configureIconButton(forwardButton, R.drawable.lucide_chevron_left, "前进", rotation = 180f) {
            executeAction("forward", emptyMap()) {}
        }
        configureIconButton(reloadButton, R.drawable.lucide_refresh_cw, "刷新") {
            executeAction("reload", emptyMap()) {}
        }
        configureIconButton(newTabButton, R.drawable.lucide_plus, "新建标签页") {
            executeAction("tab_new", emptyMap()) {}
        }
        configureIconButton(moreButton, R.drawable.lucide_layout_list, "更多浏览器工具") {
            showMoreMenu(it)
        }
        navRow.addView(backButton)
        navRow.addView(forwardButton)
        navRow.addView(reloadButton)
        navRow.addView(newTabButton)
        navRow.addView(
            View(context),
            LinearLayout.LayoutParams(0, 1, 1f),
        )
        uaButton.apply {
            minimumWidth = dp(52)
            gravity = Gravity.CENTER
            typeface = Typeface.MONOSPACE
            textSize = 12f
            setPadding(dp(12), dp(9), dp(12), dp(9))
            setOnClickListener {
                val nextMode = if (activeTabOrNull()?.userAgentMode == NativeBrowserUserAgentMode.DESKTOP) {
                    NativeBrowserUserAgentMode.MOBILE
                } else {
                    NativeBrowserUserAgentMode.DESKTOP
                }
                executeAction("set_ua", mapOf("mode" to nextMode.value)) {}
            }
        }
        navRow.addView(uaButton)
        navRow.addView(moreButton)

        val addressRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = actionButtonDrawable(
                NativeUiPalette.surfaceAlt,
                strokeColor = NativeUiPalette.border,
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(10)
            }
        }
        addressInput.apply {
            setTextColor(NativeUiPalette.textPrimary)
            setHintTextColor(NativeUiPalette.textSubtle)
            hint = "输入网址、后台地址或 localhost"
            background = actionButtonDrawable(
                NativeUiPalette.background,
                strokeColor = NativeUiPalette.borderStrong,
            )
            typeface = Typeface.MONOSPACE
            textSize = 12f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            setPadding(dp(14), dp(12), dp(14), dp(12))
            setSingleLine(true)
            setOnEditorActionListener { _, _, _ ->
                executeAction("open", mapOf("url" to addressInput.text?.toString().orEmpty())) {}
                true
            }
        }
        addressRow.addView(
            addressInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = dp(8)
            },
        )
        addressRow.addView(
            createActionButton("打开") {
                executeAction("open", mapOf("url" to addressInput.text?.toString().orEmpty())) {}
            },
        )

        recentActionsColumn.apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = actionButtonDrawable(
                NativeUiPalette.surface,
                strokeColor = NativeUiPalette.border,
            )
            visibility = View.GONE
        }

        inspectorColumn.apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = actionButtonDrawable(
                NativeUiPalette.surface,
                strokeColor = NativeUiPalette.borderStrong,
            )
            visibility = View.GONE
        }
        inspectorToggleButton.apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            text = "显示检查器"
            setOnClickListener {
                showInspector = !showInspector
                if (showInspector && inspectorItems.isEmpty() && !inspectorLoading) {
                    loadInspector(inspectorMode)
                }
                updateInspectorUi()
            }
        }
        inspectorElementsButton.apply {
            setOnClickListener { loadInspector(NativeBrowserInspectorMode.INTERACTABLES) }
        }
        inspectorLinksButton.apply {
            setOnClickListener { loadInspector(NativeBrowserInspectorMode.LINKS) }
        }
        inspectorErrorView.apply {
            setTextColor(Color.parseColor("#FCA5A5"))
            textSize = 11f
            visibility = View.GONE
        }
        inspectorLoadingView.apply {
            setTextColor(Color.parseColor("#FBBF24"))
            textSize = 11f
            text = "正在读取当前页面…"
            visibility = View.GONE
        }
        val inspectorActionsRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(inspectorElementsButton)
            addView(inspectorLinksButton)
        }
        val inspectorScroll = ScrollView(context).apply {
            isFillViewport = true
            addView(
                inspectorItemsColumn.apply {
                    orientation = LinearLayout.VERTICAL
                },
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        inspectorColumn.addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    TextView(context).apply {
                        text = "页面检查器"
                        setTextColor(Color.WHITE)
                        textSize = 12f
                        typeface = Typeface.DEFAULT_BOLD
                    },
                    LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(inspectorToggleButton)
            },
        )
        inspectorColumn.addView(inspectorActionsRow)
        inspectorColumn.addView(inspectorLoadingView)
        inspectorColumn.addView(inspectorErrorView)
        inspectorColumn.addView(
            inspectorScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(210),
            ).apply {
                topMargin = dp(8)
            },
        )

        webViewContainer.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ).apply {
            topMargin = dp(10)
        }
        webViewContainer.background = actionButtonDrawable(
            NativeUiPalette.surface,
            strokeColor = NativeUiPalette.borderStrong,
        )
        webViewContainer.clipToOutline = true
        webViewContainer.setPadding(dp(1), dp(1), dp(1), dp(1))

        rootLayout.addView(statusColumn)
        rootLayout.addView(tabScroller)
        rootLayout.addView(navRow)
        rootLayout.addView(addressRow)
        rootLayout.addView(recentActionsColumn)
        rootLayout.addView(inspectorColumn)
        rootLayout.addView(webViewContainer)
        bindInsets()
        addView(
            rootLayout,
            LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun createActionButton(label: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            text = label
            setTextColor(NativeUiPalette.textPrimary)
            gravity = Gravity.CENTER
            textSize = 12f
            typeface = Typeface.MONOSPACE
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = actionButtonDrawable(
                NativeUiPalette.accentSoft,
                strokeColor = NativeUiPalette.accent,
            )
            setOnClickListener { onClick() }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginEnd = dp(6)
            }
        }
    }

    private fun configureIconButton(
        target: FrameLayout,
        iconRes: Int,
        description: String,
        rotation: Float = 0f,
        onClick: (View) -> Unit,
    ) {
        target.removeAllViews()
        target.background = actionButtonDrawable(
            NativeUiPalette.surfaceRaised,
            strokeColor = NativeUiPalette.borderStrong,
        )
        target.setOnClickListener { onClick(it) }
        val iconDrawable = ContextCompat.getDrawable(context, iconRes)?.mutate()
        if (iconDrawable != null) {
            DrawableCompat.setTint(iconDrawable, NativeUiPalette.textPrimary)
        }
        target.addView(
            ImageView(context).apply {
                setImageDrawable(iconDrawable)
                this.rotation = rotation
                contentDescription = description
            },
            LayoutParams(dp(18), dp(18), Gravity.CENTER),
        )
        target.layoutParams = LinearLayout.LayoutParams(dp(38), dp(38)).apply {
            marginEnd = dp(6)
        }
    }

    private fun createSmallActionButton(
        label: String,
        active: Boolean = false,
        onClick: () -> Unit,
    ): TextView {
        return TextView(context).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(NativeUiPalette.textPrimary)
            textSize = 11f
            typeface = Typeface.MONOSPACE
            setPadding(dp(10), dp(7), dp(10), dp(7))
            background = actionButtonDrawable(
                if (active) NativeUiPalette.accentSoft else NativeUiPalette.surfaceAlt,
                strokeColor = if (active) NativeUiPalette.accent else NativeUiPalette.borderStrong,
            )
            setOnClickListener { onClick() }
        }.also { button ->
            button.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginEnd = dp(6)
            }
        }
    }

    private fun actionButtonDrawable(color: Int, strokeColor: Int? = null) =
        GradientDrawable().apply {
            cornerRadius = dp(14).toFloat()
            setColor(color)
            if (strokeColor != null) {
                setStroke(dp(1), strokeColor)
            }
        }

    private fun activeTabOrNull(): NativeBrowserTab? = tabs.getOrNull(activeTabIndex)

    private fun attachActiveTab() {
        val tab = activeTabOrNull() ?: return
        webViewContainer.removeAllViews()
        webViewContainer.addView(
            tab.webView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        syncChrome()
    }

    private fun syncChrome() {
        val tab = activeTabOrNull() ?: return
        refreshTabNavigationState(tab)
        if (!addressInput.hasFocus()) {
            val currentText = addressInput.text?.toString().orEmpty()
            if (currentText != tab.currentUrl) {
                addressInput.setText(tab.currentUrl)
                addressInput.setSelection(addressInput.text?.length ?: 0)
            }
        }
        bridgeStatusView.text = if (tab.loading) {
            "浏览器自动化已连接 · 页面加载中"
        } else if (tab.error.isNotEmpty()) {
            "浏览器自动化已连接 · 页面异常"
        } else {
            "浏览器自动化已连接 · ${tab.title.ifBlank { "Browser" }}"
        }
        bridgeMetaView.text = when {
            tab.error.isNotEmpty() -> tab.error
            tab.currentUrl.isNotEmpty() -> tab.currentUrl
            else -> "Codex 浏览器原生页"
        }
        uaButton.text = tab.userAgentMode.label
        uaButton.setTextColor(
            if (tab.userAgentMode == NativeBrowserUserAgentMode.DESKTOP) {
                NativeUiPalette.warning
            } else {
                NativeUiPalette.textPrimary
            },
        )
        uaButton.gravity = Gravity.CENTER
        uaButton.textSize = 12f
        uaButton.typeface = Typeface.MONOSPACE
        uaButton.setPadding(dp(12), dp(10), dp(12), dp(10))
        uaButton.background = actionButtonDrawable(
            if (tab.userAgentMode == NativeBrowserUserAgentMode.DESKTOP) {
                Color.parseColor("#29F59E0B")
            } else {
                NativeUiPalette.surfaceRaised
            },
            strokeColor = if (tab.userAgentMode == NativeBrowserUserAgentMode.DESKTOP) {
                NativeUiPalette.warning
            } else {
                NativeUiPalette.borderStrong
            },
        )
        backButton.alpha = if (tab.canGoBack) 1f else 0.45f
        forwardButton.alpha = if (tab.canGoForward) 1f else 0.45f
        renderTabStrip()
        renderRecentActions()
        updateInspectorUi()
    }

    private fun renderTabStrip() {
        tabStrip.removeAllViews()
        tabs.forEachIndexed { index, tab ->
            tabStrip.addView(
                TextView(context).apply {
                    val title = tab.title.ifBlank { "标签页 ${index + 1}" }.take(22)
                    text = "${tab.userAgentMode.label} · $title"
                    setTextColor(
                        if (index == activeTabIndex) NativeUiPalette.accent else NativeUiPalette.textPrimary,
                    )
                    textSize = 11f
                    typeface = Typeface.MONOSPACE
                    setPadding(dp(12), dp(8), dp(12), dp(8))
                    background = actionButtonDrawable(
                        if (index == activeTabIndex) NativeUiPalette.accentSoft else NativeUiPalette.surfaceAlt,
                        strokeColor = if (index == activeTabIndex) NativeUiPalette.accent else NativeUiPalette.borderStrong,
                    )
                    setOnClickListener {
                        activeIndexSafeSet(index)
                    }
                }.also { button ->
                    button.layoutParams = LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        marginEnd = dp(6)
                    }
                },
            )
        }
        tabStrip.addView(createSmallActionButton("关闭当前") {
            executeAction("tab_close", emptyMap()) {}
        })
    }

    private fun bindInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = dp(12) + systemBars.left,
                right = dp(12) + systemBars.right,
                bottom = dp(12) + systemBars.bottom,
            )
            insets
        }
        ViewCompat.requestApplyInsets(rootLayout)
    }

    private fun recordAction(action: String, result: Map<String, Any?>) {
        val message = result["message"]?.toString()?.trim().orEmpty().ifEmpty { action }
        val ok = when (val value = result["ok"]) {
            is Boolean -> value
            else -> true
        }
        if (!ok) {
            showRecentActions = true
        }
        recentActions.addFirst(NativeBrowserUiActionEntry(action = action, message = message, ok = ok))
        while (recentActions.size > 3) {
            recentActions.removeLast()
        }
    }

    private fun renderRecentActions() {
        recentActionsColumn.removeAllViews()
        if (!showRecentActions || recentActions.isEmpty()) {
            recentActionsColumn.visibility = View.GONE
            return
        }
        recentActionsColumn.visibility = View.VISIBLE
        recentActionsColumn.addView(
            TextView(context).apply {
                text = "最近浏览器操作"
                setTextColor(NativeUiPalette.textPrimary)
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
            },
        )
        recentActions.forEach { entry ->
            recentActionsColumn.addView(
                TextView(context).apply {
                    text = "${if (entry.ok) "成功" else "失败"} · ${entry.action} · ${entry.message}"
                    setTextColor(if (entry.ok) NativeUiPalette.successSoft else NativeUiPalette.dangerSoft)
                    textSize = 11f
                    typeface = Typeface.MONOSPACE
                    setPadding(0, dp(6), 0, 0)
                },
            )
        }
    }

    private fun updateInspectorUi() {
        val shouldShow = showInspector || inspectorLoading || inspectorItems.isNotEmpty()
        inspectorColumn.visibility = if (shouldShow) View.VISIBLE else View.GONE
        inspectorToggleButton.text = if (showInspector) "隐藏检查器" else "显示检查器"
        inspectorLoadingView.visibility = if (inspectorLoading) View.VISIBLE else View.GONE
        inspectorErrorView.visibility = if (inspectorError.isNotEmpty()) View.VISIBLE else View.GONE
        inspectorErrorView.text = inspectorError
        inspectorElementsButton.text = if (inspectorMode == NativeBrowserInspectorMode.INTERACTABLES) "元素中" else "元素"
        inspectorLinksButton.text = if (inspectorMode == NativeBrowserInspectorMode.LINKS) "链接中" else "链接"
        inspectorElementsButton.background = actionButtonDrawable(
            if (inspectorMode == NativeBrowserInspectorMode.INTERACTABLES) NativeUiPalette.accentSoft else NativeUiPalette.surfaceAlt,
            strokeColor = if (inspectorMode == NativeBrowserInspectorMode.INTERACTABLES) NativeUiPalette.accent else NativeUiPalette.borderStrong,
        )
        inspectorLinksButton.background = actionButtonDrawable(
            if (inspectorMode == NativeBrowserInspectorMode.LINKS) NativeUiPalette.accentSoft else NativeUiPalette.surfaceAlt,
            strokeColor = if (inspectorMode == NativeBrowserInspectorMode.LINKS) NativeUiPalette.accent else NativeUiPalette.borderStrong,
        )
        inspectorElementsButton.setTextColor(
            if (inspectorMode == NativeBrowserInspectorMode.INTERACTABLES) NativeUiPalette.accent else NativeUiPalette.textPrimary,
        )
        inspectorLinksButton.setTextColor(
            if (inspectorMode == NativeBrowserInspectorMode.LINKS) NativeUiPalette.accent else NativeUiPalette.textPrimary,
        )
        inspectorElementsButton.gravity = Gravity.CENTER
        inspectorLinksButton.gravity = Gravity.CENTER
        inspectorElementsButton.textSize = 11f
        inspectorLinksButton.textSize = 11f
        inspectorElementsButton.typeface = Typeface.MONOSPACE
        inspectorLinksButton.typeface = Typeface.MONOSPACE
        inspectorElementsButton.setPadding(dp(10), dp(8), dp(10), dp(8))
        inspectorLinksButton.setPadding(dp(10), dp(8), dp(10), dp(8))
        renderInspectorItems()
    }

    private fun renderInspectorItems() {
        inspectorItemsColumn.removeAllViews()
        if (inspectorItems.isEmpty()) {
            inspectorItemsColumn.addView(
                TextView(context).apply {
                    text = if (inspectorMode == NativeBrowserInspectorMode.LINKS) {
                        "当前页面没有可见链接。"
                    } else {
                        "当前页面没有可见可交互元素。"
                    }
                    setTextColor(Color.parseColor("#9CA3AF"))
                    textSize = 11f
                    setPadding(0, dp(4), 0, 0)
                },
            )
            return
        }
        inspectorItems.forEach { item ->
            inspectorItemsColumn.addView(
                if (inspectorMode == NativeBrowserInspectorMode.LINKS) {
                    createLinkInspectorCard(item)
                } else {
                    createInteractableInspectorCard(item)
                },
            )
        }
    }

    private fun createLinkInspectorCard(item: Map<String, Any?>): View {
        val href = item["href"]?.toString()?.trim().orEmpty()
        val text = item["text"]?.toString()?.trim().orEmpty().ifEmpty { "(无链接文字)" }
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = actionButtonDrawable(Color.parseColor("#111111"), strokeColor = Color.parseColor("#252525"))
            addView(
                TextView(context).apply {
                    setTextColor(Color.WHITE)
                    textSize = 12f
                    typeface = Typeface.DEFAULT_BOLD
                    this.text = text
                },
            )
            addView(
                TextView(context).apply {
                    setTextColor(Color.parseColor("#9CA3AF"))
                    textSize = 11f
                    typeface = Typeface.MONOSPACE
                    this.text = href
                    setPadding(0, dp(4), 0, 0)
                },
            )
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(createSmallActionButton("复制") { copyToClipboard(href, "链接地址") })
                    addView(createSmallActionButton("打开") {
                        executeAction("open", mapOf("url" to href)) {}
                    })
                },
            )
        }.also { card ->
            card.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
        }
    }

    private fun createInteractableInspectorCard(item: Map<String, Any?>): View {
        val selector = item["selector"]?.toString()?.trim().orEmpty()
        val label = item["text"]?.toString()?.trim().orEmpty()
            .ifEmpty { item["aria"]?.toString()?.trim().orEmpty() }
            .ifEmpty { item["tag"]?.toString()?.trim().orEmpty().ifEmpty { "element" } }
        val meta = listOf(
            item["tag"]?.toString()?.trim().orEmpty(),
            item["role"]?.toString()?.trim().orEmpty(),
            item["type"]?.toString()?.trim().orEmpty(),
            item["placeholder"]?.toString()?.trim().orEmpty(),
        ).filter { it.isNotEmpty() }.joinToString(" · ")
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = actionButtonDrawable(Color.parseColor("#111111"), strokeColor = Color.parseColor("#252525"))
            addView(
                TextView(context).apply {
                    setTextColor(Color.WHITE)
                    textSize = 12f
                    typeface = Typeface.DEFAULT_BOLD
                    text = label
                },
            )
            if (meta.isNotEmpty()) {
                addView(
                    TextView(context).apply {
                        setTextColor(Color.parseColor("#9CA3AF"))
                        textSize = 11f
                        text = meta
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            addView(
                TextView(context).apply {
                    setTextColor(Color.parseColor("#FBBF24"))
                    textSize = 11f
                    typeface = Typeface.MONOSPACE
                    text = selector
                    setPadding(0, dp(4), 0, 0)
                },
            )
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(createSmallActionButton("复制") { copyToClipboard(selector, "选择器") })
                    addView(createSmallActionButton("标记") {
                        executeAction("highlight", mapOf("selector" to selector)) {}
                    })
                    addView(createSmallActionButton("点击") {
                        executeAction("click", mapOf("selector" to selector)) {}
                    })
                },
            )
        }.also { card ->
            card.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
        }
    }

    private fun loadInspector(mode: NativeBrowserInspectorMode) {
        inspectorMode = mode
        inspectorLoading = true
        inspectorError = ""
        inspectorItems = emptyList()
        showInspector = true
        updateInspectorUi()
        val callback: (Map<String, Any?>) -> Unit = { result ->
            val actionResult = result["actionResult"] as? Map<*, *>
            val items = actionResult?.get("items") as? List<*>
            inspectorItems = items
                ?.mapNotNull { item ->
                    val entry = item as? Map<*, *> ?: return@mapNotNull null
                    entry.entries.associate { entryItem -> entryItem.key.toString() to entryItem.value }
                }
                ?: emptyList()
            inspectorLoading = false
            val ok = when (val value = result["ok"]) {
                is Boolean -> value
                else -> true
            }
            inspectorError = if (ok) "" else result["message"]?.toString().orEmpty()
            updateInspectorUi()
        }
        if (mode == NativeBrowserInspectorMode.LINKS) {
            listLinks(filter = null, maxItems = 20, callback = callback)
        } else {
            listInteractables(filter = null, maxItems = 24, callback = callback)
        }
    }

    private fun showMoreMenu(anchor: View) {
        PopupMenu(context, anchor).apply {
            menu.add(0, MENU_RECENT_ACTIONS, 0, if (showRecentActions) "隐藏最近操作" else "显示最近操作")
            menu.add(0, MENU_INSPECTOR, 1, if (showInspector) "隐藏检查器" else "显示检查器")
            menu.add(0, MENU_SCRIPTS, 2, "脚本库")
            menu.add(0, MENU_SNAPSHOT, 3, "查看页面快照")
            menu.add(0, MENU_COPY_URL, 4, "复制当前地址")
            menu.add(0, MENU_WELCOME, 5, "打开欢迎页")
            menu.add(0, MENU_SELF_TEST, 6, "运行自检")
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    MENU_RECENT_ACTIONS -> {
                        showRecentActions = !showRecentActions
                        renderRecentActions()
                    }
                    MENU_INSPECTOR -> {
                        showInspector = !showInspector
                        if (showInspector && inspectorItems.isEmpty() && !inspectorLoading) {
                            loadInspector(inspectorMode)
                        }
                        updateInspectorUi()
                    }
                    MENU_SCRIPTS -> showScriptLibrary()
                    MENU_SNAPSHOT -> showSnapshotPreview()
                    MENU_COPY_URL -> copyToClipboard(activeTabOrNull()?.currentUrl.orEmpty(), "当前地址")
                    MENU_WELCOME -> activeTabOrNull()?.let(::loadWelcomePage)
                    MENU_SELF_TEST -> executeAction("self_test", emptyMap()) {}
                }
                true
            }
            show()
        }
    }

    private fun activeIndexSafeSet(index: Int) {
        if (index !in tabs.indices || index == activeTabIndex) {
            return
        }
        activeTabIndex = index
        attachActiveTab()
    }

    private fun showSnapshotPreview() {
        captureSnapshot(selector = null, maxLength = 3200) { result ->
            val actionResult = result["actionResult"] as? Map<*, *>
            val title = actionResult?.get("title")?.toString()?.trim().orEmpty().ifEmpty { "当前页面" }
            val url = actionResult?.get("url")?.toString()?.trim().orEmpty()
            val text = actionResult?.get("text")?.toString()?.trim().orEmpty()
            val summary = buildString {
                append(title)
                if (url.isNotEmpty()) {
                    append("\n")
                    append(url)
                }
                if (text.isNotEmpty()) {
                    append("\n\n")
                    append(text.take(1800))
                }
            }
            AlertDialog.Builder(context)
                .setTitle("页面快照")
                .setMessage(summary.ifEmpty { "当前页面没有可读取的快照内容。" })
                .setPositiveButton("复制") { _, _ ->
                    copyToClipboard(summary, "页面快照")
                }
                .setNegativeButton("关闭", null)
                .show()
        }
    }

    private fun copyToClipboard(text: String, label: String) {
        if (text.trim().isEmpty()) {
            return
        }
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    private fun showScriptLibrary() {
        val automationScripts = loadStoredAutomationScripts()
        val userScripts = loadStoredUserScripts()
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(8))
            addView(
                TextView(context).apply {
                    text = "复用已有浏览器流程，或查看传统网站脚本源码。"
                    setTextColor(Color.parseColor("#D1D5DB"))
                    textSize = 12f
                },
            )
            addView(
                TextView(context).apply {
                    text = "自动化脚本 ${automationScripts.size} 个 · 传统脚本 ${userScripts.size} 个"
                    setTextColor(Color.parseColor("#9CA3AF"))
                    textSize = 11f
                    setPadding(0, dp(6), 0, dp(10))
                },
            )
            if (automationScripts.isEmpty()) {
                addView(createEmptySection("还没有已保存的 Codex 自动化流程。"))
            } else {
                addView(createSectionTitle("Codex 自动化流程"))
                automationScripts.forEach { script ->
                    addView(createAutomationScriptCard(script))
                }
            }
            if (userScripts.isEmpty()) {
                addView(createEmptySection("还没有已保存的传统网站脚本。"))
            } else {
                addView(createSectionTitle("传统网站脚本"))
                userScripts.forEach { script ->
                    addView(createUserScriptCard(script))
                }
            }
        }
        AlertDialog.Builder(context)
            .setTitle("浏览器脚本库")
            .setView(
                ScrollView(context).apply {
                    isFillViewport = true
                    addView(
                        content,
                        ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                },
            )
            .setPositiveButton("关闭", null)
            .show()
    }

    private fun createSectionTitle(label: String): View {
        return TextView(context).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(8), 0, dp(8))
        }
    }

    private fun createEmptySection(message: String): View {
        return TextView(context).apply {
            text = message
            setTextColor(Color.parseColor("#9CA3AF"))
            textSize = 11f
            setPadding(0, dp(4), 0, dp(12))
        }
    }

    private fun createAutomationScriptCard(script: NativeBrowserStoredScript): View {
        val meta = buildList {
            add("${script.steps.size} 步")
            if (script.runCount > 0) {
                add("运行 ${script.runCount} 次")
            }
            formatStoredDate(script.lastRunAt)?.let { add("上次 $it") }
            formatStoredDate(script.updatedAt)?.let { add("更新 $it") }
        }.joinToString(" · ")
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = actionButtonDrawable(Color.parseColor("#111111"), strokeColor = Color.parseColor("#252525"))
            addView(
                TextView(context).apply {
                    text = script.fileName
                    setTextColor(Color.WHITE)
                    textSize = 12f
                    typeface = Typeface.DEFAULT_BOLD
                },
            )
            if (script.description.isNotEmpty()) {
                addView(
                    TextView(context).apply {
                        text = script.description
                        setTextColor(Color.parseColor("#D1D5DB"))
                        textSize = 11f
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            if (meta.isNotEmpty()) {
                addView(
                    TextView(context).apply {
                        text = meta
                        setTextColor(Color.parseColor("#9CA3AF"))
                        textSize = 10.5f
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            if (script.sourceUrl.isNotEmpty()) {
                addView(
                    TextView(context).apply {
                        text = script.sourceUrl
                        setTextColor(Color.parseColor("#FBBF24"))
                        textSize = 10.5f
                        typeface = Typeface.MONOSPACE
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(0, dp(8), 0, 0)
                    addView(createSmallActionButton("运行") { promptAndRunScript(script) })
                    addView(createSmallActionButton("步骤") { showAutomationScriptDetails(script) })
                    addView(createSmallActionButton("复制命令") {
                        copyToClipboard(script.quickCommand, "脚本命令")
                    })
                },
            )
        }.also { card ->
            card.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
        }
    }

    private fun createUserScriptCard(script: NativeBrowserStoredUserScript): View {
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = actionButtonDrawable(Color.parseColor("#111111"), strokeColor = Color.parseColor("#252525"))
            addView(
                TextView(context).apply {
                    text = script.name
                    setTextColor(Color.WHITE)
                    textSize = 12f
                    typeface = Typeface.DEFAULT_BOLD
                },
            )
            if (script.description.isNotEmpty()) {
                addView(
                    TextView(context).apply {
                        text = script.description
                        setTextColor(Color.parseColor("#D1D5DB"))
                        textSize = 11f
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            val matchLine = script.matches.joinToString(" · ").ifEmpty { "*://*/*" }
            addView(
                TextView(context).apply {
                    text = matchLine
                    setTextColor(Color.parseColor("#9CA3AF"))
                    textSize = 10.5f
                    typeface = Typeface.MONOSPACE
                    setPadding(0, dp(4), 0, 0)
                },
            )
            formatStoredDate(script.updatedAt)?.let { formatted ->
                addView(
                    TextView(context).apply {
                        text = "更新 $formatted"
                        setTextColor(Color.parseColor("#9CA3AF"))
                        textSize = 10.5f
                        setPadding(0, dp(4), 0, 0)
                    },
                )
            }
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(0, dp(8), 0, 0)
                    addView(createSmallActionButton("看源码") { showUserScriptSource(script) })
                    addView(createSmallActionButton("复制源码") {
                        copyToClipboard(script.code, "${script.name} 源码")
                    })
                },
            )
        }.also { card ->
            card.layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(8)
            }
        }
    }

    private fun showAutomationScriptDetails(script: NativeBrowserStoredScript) {
        val detail = buildString {
            append(script.fileName)
            if (script.description.isNotEmpty()) {
                append("\n")
                append(script.description)
            }
            if (script.sourceUrl.isNotEmpty()) {
                append("\n\n来源: ")
                append(script.sourceUrl)
            }
            script.steps.forEachIndexed { index, step ->
                append("\n\n")
                append(index + 1)
                append(". ")
                append(step.action)
                if (step.note.isNotEmpty()) {
                    append(" · ")
                    append(step.note)
                }
                if (step.payload.isNotEmpty()) {
                    append("\n")
                    append(JSONObject(step.payload).toString(2))
                }
            }
        }
        AlertDialog.Builder(context)
            .setTitle("脚本步骤")
            .setMessage(detail)
            .setPositiveButton("复制内容") { _, _ ->
                copyToClipboard(detail, "脚本步骤")
            }
            .setNegativeButton("关闭", null)
            .show()
    }

    private fun showUserScriptSource(script: NativeBrowserStoredUserScript) {
        val sourceView = EditText(context).apply {
            setText(script.code)
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.BLACK)
            typeface = Typeface.MONOSPACE
            textSize = 11f
            setHorizontallyScrolling(true)
            minLines = 12
            maxLines = 22
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            isFocusable = false
            isClickable = true
        }
        AlertDialog.Builder(context)
            .setTitle(script.name)
            .setView(sourceView)
            .setPositiveButton("复制源码") { _, _ ->
                copyToClipboard(script.code, "${script.name} 源码")
            }
            .setNegativeButton("关闭", null)
            .show()
    }

    private fun promptAndRunScript(script: NativeBrowserStoredScript) {
        if (script.variables.isEmpty()) {
            runStoredScript(script, emptyMap())
            return
        }
        val inputViews = linkedMapOf<String, EditText>()
        val form = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(10), dp(18), dp(0))
        }
        script.variables.forEach { variable ->
            form.addView(
                TextView(context).apply {
                    text = variable
                    setTextColor(Color.WHITE)
                    textSize = 12f
                    setPadding(0, dp(8), 0, dp(4))
                },
            )
            val input = EditText(context).apply {
                setTextColor(Color.WHITE)
                setHintTextColor(Color.parseColor("#7C7C7C"))
                hint = "{{${variable}}}"
                background = actionButtonDrawable(Color.parseColor("#101010"), strokeColor = Color.parseColor("#252525"))
                setPadding(dp(10), dp(10), dp(10), dp(10))
                setSingleLine(true)
            }
            inputViews[variable] = input
            form.addView(input)
        }
        AlertDialog.Builder(context)
            .setTitle("运行脚本变量")
            .setView(form)
            .setPositiveButton("运行") { _, _ ->
                val values = inputViews.entries.associate { (key, view) ->
                    key to view.text?.toString().orEmpty()
                }
                runStoredScript(script, values)
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun runStoredScript(
        script: NativeBrowserStoredScript,
        variables: Map<String, String>,
    ) {
        val logView = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 11f
            typeface = Typeface.MONOSPACE
            setPadding(dp(18), dp(14), dp(18), dp(14))
            text = "准备运行 ${script.fileName} …"
        }
        val dialog = AlertDialog.Builder(context)
            .setTitle("运行自动化脚本")
            .setView(
                ScrollView(context).apply {
                    addView(
                        logView,
                        ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                },
            )
            .setNegativeButton("关闭", null)
            .create()
        dialog.show()
        val logLines = mutableListOf<String>()
        fun appendLog(line: String) {
            logLines += line
            logView.text = logLines.joinToString("\n")
        }
        fun finishRun(success: Boolean, message: String) {
            appendLog(message)
            if (success) {
                persistStoredScriptRun(script.id)
            }
        }
        fun runStep(index: Int) {
            if (index >= script.steps.size) {
                finishRun(true, "全部 ${script.steps.size} 步已完成。")
                return
            }
            val step = script.steps[index]
            val action = normalizeStoredScriptAction(step.action)
            if (action !in RUNNABLE_SCRIPT_ACTIONS) {
                finishRun(false, "第 ${index + 1} 步不支持运行: ${step.action}")
                return
            }
            val resolvedPayload = step.payload.resolveScriptVariables(variables)
            appendLog("步骤 ${index + 1}/${script.steps.size} · $action")
            executeAction(action, resolvedPayload) { result ->
                val ok = result["ok"] != false
                val message = result["message"]?.toString()?.trim().orEmpty()
                    .ifEmpty { if (ok) "已完成。" else "执行失败。" }
                appendLog("${if (ok) "成功" else "失败"} · $message")
                if (!ok) {
                    finishRun(false, "脚本在第 ${index + 1} 步停止。")
                    return@executeAction
                }
                runStep(index + 1)
            }
        }
        runStep(0)
    }

    private fun loadStoredAutomationScripts(): List<NativeBrowserStoredScript> {
        val raw = flutterPrefs().getString(PREF_AUTOMATION_SCRIPTS, null)?.trim().orEmpty()
        if (raw.isEmpty()) {
            return emptyList()
        }
        val decoded = runCatching { JSONTokener(raw).nextValue() }.getOrNull() as? JSONArray
            ?: return emptyList()
        val scripts = mutableListOf<NativeBrowserStoredScript>()
        for (index in 0 until decoded.length()) {
            val item = decoded.optJSONObject(index) ?: continue
            val id = item.optString("id").trim()
            val fileName = item.optString("fileName").trim()
            val rawSteps = item.optJSONArray("steps") ?: JSONArray()
            val steps = mutableListOf<NativeBrowserStoredScriptStep>()
            for (stepIndex in 0 until rawSteps.length()) {
                val stepItem = rawSteps.optJSONObject(stepIndex) ?: continue
                val action = stepItem.optString("action").trim()
                if (action.isEmpty()) {
                    continue
                }
                val payload = (stepItem.optJSONObject("payload") ?: JSONObject()).toMap()
                steps += NativeBrowserStoredScriptStep(
                    action = action,
                    payload = payload,
                    note = stepItem.optString("note").trim(),
                )
            }
            if (id.isEmpty() || fileName.isEmpty() || steps.isEmpty()) {
                continue
            }
            scripts += NativeBrowserStoredScript(
                id = id,
                fileName = fileName,
                description = item.optString("description").trim(),
                steps = steps,
                variables = (item.optJSONArray("variables") ?: JSONArray()).toStringList(),
                sourceUrl = item.optString("sourceUrl").trim(),
                sourceTitle = item.optString("sourceTitle").trim(),
                updatedAt = item.optString("updatedAt").trim(),
                lastRunAt = item.optString("lastRunAt").trim(),
                runCount = item.optInt("runCount", 0),
            )
        }
        return scripts.sortedByDescending { it.updatedAt }
    }

    private fun loadStoredUserScripts(): List<NativeBrowserStoredUserScript> {
        val raw = flutterPrefs().getString(PREF_USER_SCRIPTS, null)?.trim().orEmpty()
        if (raw.isEmpty()) {
            return emptyList()
        }
        val decoded = runCatching { JSONTokener(raw).nextValue() }.getOrNull() as? JSONArray
            ?: return emptyList()
        val scripts = mutableListOf<NativeBrowserStoredUserScript>()
        for (index in 0 until decoded.length()) {
            val item = decoded.optJSONObject(index) ?: continue
            val id = item.optString("id").trim()
            val name = item.optString("name").trim()
            val code = item.optString("code")
            if (id.isEmpty() || name.isEmpty() || code.isBlank()) {
                continue
            }
            scripts += NativeBrowserStoredUserScript(
                id = id,
                name = name,
                description = item.optString("description").trim(),
                code = code,
                matches = (item.optJSONArray("matches") ?: JSONArray()).toStringList(),
                updatedAt = item.optString("updatedAt").trim(),
            )
        }
        return scripts.sortedByDescending { it.updatedAt }
    }

    private fun persistStoredScriptRun(scriptId: String) {
        val prefs = flutterPrefs()
        val raw = prefs.getString(PREF_AUTOMATION_SCRIPTS, null)?.trim().orEmpty()
        if (raw.isEmpty()) {
            return
        }
        val decoded = runCatching { JSONTokener(raw).nextValue() }.getOrNull() as? JSONArray
            ?: return
        var changed = false
        val now = java.time.Instant.now().toString()
        for (index in 0 until decoded.length()) {
            val item = decoded.optJSONObject(index) ?: continue
            if (item.optString("id").trim() != scriptId) {
                continue
            }
            item.put("lastRunAt", now)
            item.put("updatedAt", now)
            item.put("runCount", item.optInt("runCount", 0) + 1)
            changed = true
            break
        }
        if (changed) {
            prefs.edit().putString(PREF_AUTOMATION_SCRIPTS, decoded.toString(2)).apply()
        }
    }

    private fun normalizeStoredScriptAction(action: String): String {
        val normalized = action.trim()
        return TOOL_ACTION_ALIASES[normalized] ?: normalized
    }

    private fun flutterPrefs() =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun formatStoredDate(value: String): String? {
        val normalized = value.trim()
        if (normalized.isEmpty()) {
            return null
        }
        val instant = runCatching { java.time.Instant.parse(normalized) }.getOrNull() ?: return normalized
        val local = java.time.ZonedDateTime.ofInstant(instant, java.time.ZoneId.systemDefault())
        return "%04d-%02d-%02d %02d:%02d".format(
            local.year,
            local.monthValue,
            local.dayOfMonth,
            local.hour,
            local.minute,
        )
    }

    private fun createTab(
        userAgentMode: NativeBrowserUserAgentMode = NativeBrowserUserAgentMode.MOBILE,
    ): NativeBrowserTab {
        val webView = WebView(context)
        val tab = NativeBrowserTab(
            id = nextTabId++,
            webView = webView,
            userAgentMode = userAgentMode,
        )
        configureWebView(tab)
        return tab
    }

    private fun configureWebView(tab: NativeBrowserTab) {
        val settings = tab.webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.loadsImagesAutomatically = true
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = tab.userAgentMode == NativeBrowserUserAgentMode.DESKTOP
        settings.builtInZoomControls = true
        settings.displayZoomControls = false
        settings.textZoom = 100
        settings.allowFileAccess = false
        settings.allowContentAccess = true
        settings.mediaPlaybackRequiresUserGesture = false
        settings.userAgentString = tab.userAgentMode.userAgent
        tab.webView.setBackgroundColor(Color.BLACK)
        tab.webView.webChromeClient = object : WebChromeClient() {
            override fun onReceivedTitle(view: WebView?, title: String?) {
                tab.title = title?.trim().orEmpty().ifEmpty { tab.title }
                if (tab === activeTabOrNull()) {
                    syncChrome()
                }
            }
        }
        tab.webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean = false

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                tab.loading = true
                tab.error = ""
                tab.currentUrl = url.orEmpty()
                if (tab === activeTabOrNull()) {
                    syncChrome()
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                tab.loading = false
                tab.currentUrl = url.orEmpty()
                refreshTabNavigationState(tab)
                completeNavigation(tab)
                if (tab === activeTabOrNull()) {
                    syncChrome()
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                if (request?.isForMainFrame == true) {
                    tab.loading = false
                    tab.error = error?.description?.toString().orEmpty()
                    refreshTabNavigationState(tab)
                    completeNavigation(tab)
                    if (tab === activeTabOrNull()) {
                        syncChrome()
                    }
                }
            }
        }
    }

    private fun refreshTabNavigationState(tab: NativeBrowserTab) {
        tab.currentUrl = tab.webView.url.orEmpty()
        tab.title = tab.webView.title?.trim().orEmpty().ifEmpty { tab.title }
        tab.canGoBack = tab.webView.canGoBack()
        tab.canGoForward = tab.webView.canGoForward()
    }

    private fun completeNavigation(tab: NativeBrowserTab) {
        val callbacks = tab.navigationCallbacks.toList()
        tab.navigationCallbacks.clear()
        callbacks.forEach { it.invoke() }
    }

    private fun awaitNavigation(
        tab: NativeBrowserTab,
        timeoutMs: Int = 12000,
        callback: () -> Unit,
    ) {
        if (!tab.loading) {
            callback()
            return
        }
        var completed = false
        lateinit var waiter: () -> Unit
        val timeoutRunnable = Runnable {
            if (completed) {
                return@Runnable
            }
            completed = true
            tab.navigationCallbacks.remove(waiter)
            callback()
        }
        waiter = navDone@{
            if (completed) {
                return@navDone
            }
            completed = true
            mainHandler.removeCallbacks(timeoutRunnable)
            callback()
        }
        tab.navigationCallbacks += waiter
        mainHandler.postDelayed(timeoutRunnable, timeoutMs.toLong())
    }

    private fun snapshot(
        ok: Boolean = true,
        message: String = "",
        extra: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        val active = activeTabOrNull()
        if (active != null) {
            refreshTabNavigationState(active)
        }
        return linkedMapOf<String, Any?>(
            "ok" to ok,
            "message" to message,
            "url" to (active?.currentUrl ?: ""),
            "title" to (active?.title ?: "Browser"),
            "loading" to (active?.loading ?: false),
            "error" to (active?.error ?: ""),
            "canGoBack" to (active?.canGoBack ?: false),
            "canGoForward" to (active?.canGoForward ?: false),
            "tabs" to tabs.mapIndexed { index, tab ->
                refreshTabNavigationState(tab)
                linkedMapOf<String, Any?>(
                    "id" to tab.id,
                    "active" to (index == activeTabIndex),
                    "title" to tab.title,
                    "url" to tab.currentUrl,
                    "loading" to tab.loading,
                    "error" to tab.error,
                    "canGoBack" to tab.canGoBack,
                    "canGoForward" to tab.canGoForward,
                    "userAgentMode" to tab.userAgentMode.value,
                    "userAgentLabel" to tab.userAgentMode.label,
                )
            },
            "activeTabId" to (active?.id ?: 0),
            "userAgentMode" to (active?.userAgentMode?.value ?: NativeBrowserUserAgentMode.MOBILE.value),
            "userAgentLabel" to (active?.userAgentMode?.label ?: NativeBrowserUserAgentMode.MOBILE.label),
        ).apply {
            putAll(extra)
        }
    }

    private fun normalizeUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return trimmed
        }
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            return trimmed
        }
        if (trimmed.startsWith("localhost") || trimmed.startsWith("127.0.0.1")) {
            return "http://$trimmed"
        }
        return "https://$trimmed"
    }

    private fun loadWelcomePage(tab: NativeBrowserTab) {
        tab.loading = true
        tab.error = ""
        tab.title = "Codex 浏览器自动化控制"
        tab.webView.loadDataWithBaseURL(
            "https://browser.openclaw.local/welcome",
            WELCOME_HTML,
            "text/html",
            "utf-8",
            null,
        )
        syncChrome()
    }

    private fun openUrl(url: String, callback: (Map<String, Any?>) -> Unit) {
        if (url.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The url argument cannot be empty."))
            return
        }
        val tab = activeTabOrNull() ?: run {
            callback(snapshot(ok = false, message = "Browser page is unavailable."))
            return
        }
        val target = normalizeUrl(url)
        tab.loading = true
        tab.error = ""
        tab.webView.loadUrl(target, mapOf("User-Agent" to tab.userAgentMode.userAgent))
        syncChrome()
        awaitNavigation(tab) {
            syncChrome()
            callback(snapshot(ok = tab.error.isEmpty(), message = if (tab.error.isEmpty()) "Opened $target" else tab.error))
        }
    }

    private fun goBack(callback: (Map<String, Any?>) -> Unit) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        if (!tab.webView.canGoBack()) {
            callback(snapshot(ok = false, message = "The browser cannot go back from the current page."))
            return
        }
        tab.loading = true
        tab.webView.goBack()
        syncChrome()
        awaitNavigation(tab) {
            syncChrome()
            callback(snapshot(message = "Navigated back."))
        }
    }

    private fun goForward(callback: (Map<String, Any?>) -> Unit) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        if (!tab.webView.canGoForward()) {
            callback(snapshot(ok = false, message = "The browser cannot go forward from the current page."))
            return
        }
        tab.loading = true
        tab.webView.goForward()
        syncChrome()
        awaitNavigation(tab) {
            syncChrome()
            callback(snapshot(message = "Navigated forward."))
        }
    }

    private fun reloadPage(callback: (Map<String, Any?>) -> Unit) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        tab.loading = true
        tab.webView.reload()
        syncChrome()
        awaitNavigation(tab) {
            syncChrome()
            callback(snapshot(message = "Page reloaded."))
        }
    }

    private fun openNewTab(url: String?, callback: (Map<String, Any?>) -> Unit) {
        val currentMode = activeTabOrNull()?.userAgentMode ?: NativeBrowserUserAgentMode.MOBILE
        val tab = createTab(currentMode)
        tabs += tab
        activeTabIndex = tabs.lastIndex
        attachActiveTab()
        val target = url?.trim().orEmpty()
        if (target.isEmpty()) {
            loadWelcomePage(tab)
            callback(snapshot(message = "New browser tab opened."))
            return
        }
        openUrl(target, callback)
    }

    private fun switchTab(id: Int, callback: (Map<String, Any?>) -> Unit) {
        val index = tabs.indexOfFirst { it.id == id }
        if (index < 0) {
            callback(snapshot(ok = false, message = "Browser tab was not found: $id"))
            return
        }
        activeTabIndex = index
        attachActiveTab()
        callback(snapshot(message = "Switched to browser tab $id."))
    }

    private fun closeTab(id: Int?, callback: (Map<String, Any?>) -> Unit) {
        if (tabs.isEmpty()) {
            callback(snapshot(ok = false, message = "Browser tab list is empty."))
            return
        }
        val targetId = id ?: activeTabOrNull()?.id ?: 0
        val index = tabs.indexOfFirst { it.id == targetId }
        if (index < 0) {
            callback(snapshot(ok = false, message = "Browser tab was not found: $targetId"))
            return
        }
        val removed = tabs.removeAt(index)
        removed.navigationCallbacks.clear()
        removed.webView.destroy()
        if (tabs.isEmpty()) {
            tabs += createTab()
            activeTabIndex = 0
            attachActiveTab()
            loadWelcomePage(tabs.first())
        } else {
            if (activeTabIndex >= tabs.size) {
                activeTabIndex = tabs.lastIndex
            } else if (index < activeTabIndex) {
                activeTabIndex -= 1
            }
            attachActiveTab()
        }
        callback(snapshot(message = "Browser tab closed."))
    }

    private fun setUserAgent(rawMode: String, callback: (Map<String, Any?>) -> Unit) {
        val nextMode = NativeBrowserUserAgentMode.parse(rawMode)
        if (nextMode == null) {
            callback(snapshot(ok = false, message = "Unsupported browser user-agent mode: $rawMode"))
            return
        }
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        tab.userAgentMode = nextMode
        val settings = tab.webView.settings
        settings.userAgentString = nextMode.userAgent
        settings.loadWithOverviewMode = nextMode == NativeBrowserUserAgentMode.DESKTOP
        settings.useWideViewPort = true
        syncChrome()
        val currentUrl = tab.currentUrl.trim()
        if (currentUrl.isEmpty() || currentUrl == "about:blank") {
            callback(snapshot(message = "Browser user-agent switched to ${nextMode.label}."))
            return
        }
        tab.loading = true
        tab.webView.loadUrl(currentUrl, mapOf("User-Agent" to nextMode.userAgent))
        awaitNavigation(tab) {
            syncChrome()
            callback(snapshot(message = "Browser user-agent switched to ${nextMode.label}."))
        }
    }

    private fun runSelfTest(callback: (Map<String, Any?>) -> Unit) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        tab.loading = true
        tab.error = ""
        tab.title = "OpenClaw Browser Self Test"
        tab.webView.loadDataWithBaseURL(
            "https://browser.openclaw.local/self-test",
            SELF_TEST_HTML,
            "text/html",
            "utf-8",
            null,
        )
        syncChrome()
        awaitNavigation(tab) {
            runJsonScript(
                tab,
                """
                    (() => {
                      const marker = document.querySelector('[data-openclaw-self-test="ready"]');
                      return JSON.stringify({
                        ok: Boolean(marker) && window.__openclawBrowserSelfTest === 'ready',
                        title: document.title || '',
                        markerText: marker ? (marker.textContent || '').trim().slice(0, 160) : '',
                        href: location.href || ''
                      });
                    })();
                """.trimIndent(),
            ) { decoded ->
                if (decoded == null) {
                    callback(snapshot(ok = false, message = "Self-test page loaded, but JavaScript evaluation failed."))
                    return@runJsonScript
                }
                callback(
                    snapshot(
                        ok = decoded.optBoolean("ok"),
                        message = if (decoded.optBoolean("ok")) {
                            "Browser self-test passed."
                        } else {
                            "Self-test page loaded, but the readiness marker was not found."
                        },
                        extra = mapOf("actionResult" to decoded.toMap()),
                    ),
                )
            }
        }
    }

    private fun runHealthCheck(
        quietWindowMs: Int,
        timeoutMs: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        val safeQuietWindowMs = quietWindowMs.coerceIn(100, 5000)
        val safeTimeoutMs = timeoutMs.coerceIn(safeQuietWindowMs, 30000)
        pollJsonScript(
            tab = tab,
            timeoutMs = safeTimeoutMs,
            intervalMs = 250,
            script = """
                (() => {
                  const quietWindowMs = $safeQuietWindowMs;
                  const now = Date.now();
                  const state = document.readyState || 'unknown';
                  const body = document.body;
                  const root = document.documentElement;
                  const lastMutation = window.__openclawLastDomMutationAt || 0;
                  if (!window.__openclawHealthObserver && document.documentElement) {
                    window.__openclawLastDomMutationAt = now;
                    window.__openclawHealthObserver = new MutationObserver(() => {
                      window.__openclawLastDomMutationAt = Date.now();
                    });
                    window.__openclawHealthObserver.observe(document.documentElement, {
                      childList: true, subtree: true, attributes: true, characterData: true
                    });
                  }
                  const resources = performance.getEntriesByType('resource');
                  const recentResources = resources.filter((entry) => now - entry.responseEnd < quietWindowMs);
                  const domQuiet = now - lastMutation >= quietWindowMs;
                  const ready = state === 'complete' && Boolean(body) && Boolean(root) && domQuiet && recentResources.length === 0;
                  return JSON.stringify({
                    ok: ready,
                    javascript: true,
                    dom: Boolean(body) && Boolean(root),
                    readyState: state,
                    domQuiet,
                    recentResourceCount: recentResources.length,
                    url: location.href || '',
                    title: document.title || ''
                  });
                })();
            """.trimIndent(),
            predicate = { it.optBoolean("ok") },
            onSuccess = { decoded ->
                callback(
                    snapshot(
                        message = "Browser health check passed: DOM, JavaScript, and network idle are ready.",
                        extra = mapOf("actionResult" to decoded.toMap()),
                    ),
                )
            },
            onTimeout = {
                callback(
                    snapshot(
                        ok = false,
                        message = "Timed out waiting for DOM and network idle; the page may still be hydrating.",
                    ),
                )
            },
        )
    }

    private fun resetTab(url: String?, callback: (Map<String, Any?>) -> Unit) {
        val index = activeTabIndex
        val previousMode = activeTabOrNull()?.userAgentMode ?: NativeBrowserUserAgentMode.MOBILE
        val replacement = createTab(previousMode)
        val previousUrl = activeTabOrNull()?.currentUrl.orEmpty()
        activeTabOrNull()?.webView?.destroy()
        tabs[index] = replacement
        attachActiveTab()
        val target = url?.trim().orEmpty().ifEmpty { previousUrl }
        if (target.isEmpty() || target == "about:blank") {
            loadWelcomePage(replacement)
            callback(snapshot(message = "Browser tab was reset with a fresh WebView session."))
            return
        }
        openUrl(target, callback)
    }

    private fun click(selector: String, callback: (Map<String, Any?>) -> Unit) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const element = document.querySelector(selector);
                  if (!element) {
                    return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  }
                  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                  if (typeof element.focus === 'function') {
                    element.focus();
                  }
                  element.click();
                  return JSON.stringify({
                    ok: true,
                    tag: element.tagName || '',
                    text: (element.innerText || element.textContent || element.value || '').trim().slice(0, 240)
                  });
                })();
            """.trimIndent(),
            successMessage = "Click completed.",
            callback = callback,
        )
    }

    private fun typeText(
        selector: String,
        text: String,
        submit: Boolean,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const value = ${text.jsQuote()};
                  const shouldSubmit = ${submit.jsBool()};
                  const element = document.querySelector(selector);
                  if (!element) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                  if (typeof element.focus === 'function') element.focus();
                  if ('value' in element) element.value = value;
                  else if (element.isContentEditable) element.textContent = value;
                  else return JSON.stringify({ ok: false, message: 'Target element is not editable.' });
                  element.dispatchEvent(new Event('input', { bubbles: true }));
                  element.dispatchEvent(new Event('change', { bubbles: true }));
                  if (shouldSubmit) {
                    const form = element.form || element.closest('form');
                    if (form?.requestSubmit) form.requestSubmit();
                    else element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
                  }
                  return JSON.stringify({ ok: true, message: shouldSubmit ? 'Text entered and submitted.' : 'Text entered.', tag: element.tagName || '' });
                })();
            """.trimIndent(),
            successMessage = "Text entered.",
            callback = callback,
        )
    }

    private fun pasteText(
        selector: String,
        text: String,
        submit: Boolean,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const value = ${text.jsQuote()};
                  const shouldSubmit = ${submit.jsBool()};
                  const element = document.querySelector(selector);
                  if (!element) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  const tag = (element.tagName || '').toLowerCase();
                  if (!(tag === 'input' || tag === 'textarea' || element.isContentEditable)) return JSON.stringify({ ok: false, message: 'Target element is not editable.' });
                  element.focus();
                  element.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertFromPaste', data: value }));
                  if (tag === 'input' || tag === 'textarea') {
                    const prototype = tag === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
                    if (setter) setter.call(element, value); else element.value = value;
                  } else element.textContent = value;
                  element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertFromPaste', data: value }));
                  element.dispatchEvent(new Event('change', { bubbles: true }));
                  if (shouldSubmit) (element.form || element.closest?.('form'))?.requestSubmit?.();
                  return JSON.stringify({ ok: true, message: 'Text pasted with input events.' });
                })();
            """.trimIndent(),
            successMessage = "Text pasted.",
            callback = callback,
        )
    }

    private fun waitForResource(
        pattern: String,
        timeoutMs: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (pattern.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The resource pattern cannot be empty."))
            return
        }
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        pollJsonScript(
            tab = tab,
            timeoutMs = timeoutMs.coerceIn(100, 30000),
            intervalMs = 300,
            script = """
                (() => {
                  const pattern = ${pattern.jsQuote()}.toLowerCase();
                  const resources = performance.getEntriesByType('resource').filter((entry) => entry.name.toLowerCase().includes(pattern));
                  const item = resources[resources.length - 1];
                  return JSON.stringify({ ok: Boolean(item), resource: item ? { url: item.name, initiatorType: item.initiatorType } : null });
                })();
            """.trimIndent(),
            predicate = { it.optBoolean("ok") },
            onSuccess = { decoded ->
                callback(snapshot(message = "Matched a loaded page resource.", extra = mapOf("actionResult" to decoded.toMap())))
            },
            onTimeout = {
                callback(snapshot(ok = false, message = "Timed out waiting for a matching page resource."))
            },
        )
    }

    private fun waitForText(
        text: String,
        timeoutMs: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (text.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The text argument cannot be empty."))
            return
        }
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        pollJsonScript(
            tab = tab,
            timeoutMs = timeoutMs.coerceIn(100, 30000),
            intervalMs = 350,
            script = """
                (() => {
                  const needle = ${text.jsQuote()};
                  const bodyText = (document.body?.innerText || '').trim();
                  return JSON.stringify({
                    ok: bodyText.includes(needle),
                    textLength: bodyText.length
                  });
                })();
            """.trimIndent(),
            predicate = { it.optBoolean("ok") },
            onSuccess = { decoded ->
                callback(snapshot(message = "Found the requested text on the page.", extra = mapOf("actionResult" to decoded.toMap())))
            },
            onTimeout = {
                callback(snapshot(ok = false, message = "Timed out while waiting for the requested text."))
            },
        )
    }

    private fun waitForSelector(
        selector: String,
        timeoutMs: Int,
        visible: Boolean,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        pollJsonScript(
            tab = tab,
            timeoutMs = timeoutMs.coerceIn(100, 30000),
            intervalMs = 300,
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const requireVisible = ${visible.jsBool()};
                  const element = document.querySelector(selector);
                  if (!element) {
                    return JSON.stringify({ ok: false, found: false, visible: false });
                  }
                  const rect = element.getBoundingClientRect();
                  const style = window.getComputedStyle(element);
                  const isVisible = rect.width > 0 &&
                    rect.height > 0 &&
                    style.visibility !== 'hidden' &&
                    style.display !== 'none' &&
                    Number(style.opacity || '1') > 0;
                  return JSON.stringify({
                    ok: requireVisible ? isVisible : true,
                    found: true,
                    visible: isVisible,
                    tag: element.tagName || '',
                    text: (element.innerText || element.textContent || element.value || '').trim().slice(0, 240),
                    rect: {
                      x: Math.round(rect.x),
                      y: Math.round(rect.y),
                      width: Math.round(rect.width),
                      height: Math.round(rect.height)
                    }
                  });
                })();
            """.trimIndent(),
            predicate = { it.optBoolean("ok") },
            onSuccess = { decoded ->
                callback(
                    snapshot(
                        message = if (visible) {
                            "Found the visible selector on the page."
                        } else {
                            "Found the requested selector on the page."
                        },
                        extra = mapOf("actionResult" to decoded.toMap()),
                    ),
                )
            },
            onTimeout = {
                callback(
                    snapshot(
                        ok = false,
                        message = if (visible) {
                            "Timed out while waiting for the visible selector."
                        } else {
                            "Timed out while waiting for the requested selector."
                        },
                    ),
                )
            },
        )
    }

    private fun scrollPage(
        selector: String?,
        direction: String,
        pixels: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safePixels = pixels.coerceIn(50, 5000)
        val safeDirection = direction.trim().lowercase().ifEmpty { "down" }
        runActionJson(
            script = """
                (() => {
                  const selector = ${(selector?.trim().orEmpty()).jsQuote()};
                  const direction = ${safeDirection.jsQuote()};
                  const pixels = $safePixels;
                  const root = document.scrollingElement || document.documentElement || document.body;
                  const target = selector ? document.querySelector(selector) : root;
                  if (!target) {
                    return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  }
                  const isPage = target === root || target === document.body || target === document.documentElement;
                  const before = {
                    x: isPage ? window.scrollX : target.scrollLeft,
                    y: isPage ? window.scrollY : target.scrollTop
                  };
                  let dx = 0;
                  let dy = 0;
                  let absolute = false;
                  let top = 0;
                  let left = 0;
                  switch (direction) {
                    case 'up':
                      dy = -pixels;
                      break;
                    case 'left':
                      dx = -pixels;
                      break;
                    case 'right':
                      dx = pixels;
                      break;
                    case 'top':
                      absolute = true;
                      top = 0;
                      left = before.x;
                      break;
                    case 'bottom':
                      absolute = true;
                      top = isPage ? root.scrollHeight : target.scrollHeight;
                      left = before.x;
                      break;
                    case 'down':
                    default:
                      dy = pixels;
                      break;
                  }
                  if (isPage) {
                    if (absolute) window.scrollTo({ left, top, behavior: 'instant' });
                    else window.scrollBy({ left: dx, top: dy, behavior: 'instant' });
                  } else if (absolute) target.scrollTo({ left, top, behavior: 'instant' });
                  else target.scrollBy({ left: dx, top: dy, behavior: 'instant' });
                  const after = {
                    x: isPage ? window.scrollX : target.scrollLeft,
                    y: isPage ? window.scrollY : target.scrollTop
                  };
                  return JSON.stringify({
                    ok: true,
                    message: `Scrolled ${'$'}{direction}.`,
                    selector: selector || null,
                    before,
                    after
                  });
                })();
            """.trimIndent(),
            successMessage = "Scrolled page.",
            callback = callback,
        )
    }

    private fun pressKey(
        selector: String?,
        key: String,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (key.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The key argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${(selector?.trim().orEmpty()).jsQuote()};
                  const key = ${key.trim().jsQuote()};
                  let target = selector ? document.querySelector(selector) : document.activeElement;
                  if (selector && !target) {
                    return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  }
                  if (!target || target === document.body || target === document.documentElement) {
                    target = document.querySelector('input, textarea, select, button, a[href], [tabindex], [contenteditable="true"]') || document.body;
                  }
                  if (typeof target.focus === 'function') target.focus();
                  const code = key.length === 1 ? `Key${'$'}{key.toUpperCase()}` : key;
                  const eventInit = { key, code, bubbles: true, cancelable: true };
                  const down = target.dispatchEvent(new KeyboardEvent('keydown', eventInit));
                  target.dispatchEvent(new KeyboardEvent('keypress', eventInit));
                  const up = target.dispatchEvent(new KeyboardEvent('keyup', eventInit));
                  if (key === 'Enter' && down !== false) {
                    const form = target.form || target.closest?.('form');
                    if (form && typeof form.requestSubmit === 'function') form.requestSubmit();
                  }
                  return JSON.stringify({
                    ok: true,
                    message: `Pressed ${'$'}{key}.`,
                    selector: selector || null,
                    canceled: down === false || up === false
                  });
                })();
            """.trimIndent(),
            successMessage = "Key pressed.",
            callback = callback,
        )
    }

    private fun selectOption(
        selector: String,
        value: String?,
        label: String?,
        index: Int?,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        if ((value?.trim().isNullOrEmpty()) && (label?.trim().isNullOrEmpty()) && index == null) {
            callback(snapshot(ok = false, message = "Provide value, label, or index for the option to select."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const value = ${(value?.trim().orEmpty()).jsQuote()};
                  const label = ${(label?.trim().orEmpty()).jsQuote()};
                  const index = ${index?.toString() ?: "null"};
                  const select = document.querySelector(selector);
                  if (!select) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  if (select.tagName !== 'SELECT') return JSON.stringify({ ok: false, message: 'Target element is not a select.' });
                  const options = Array.from(select.options || []);
                  const normalizedLabel = label.toLowerCase();
                  let option = null;
                  if (value) option = options.find((item) => item.value === value);
                  if (!option && label) {
                    option = options.find((item) => (item.label || item.text || '').trim().toLowerCase() === normalizedLabel)
                      || options.find((item) => (item.label || item.text || '').trim().toLowerCase().includes(normalizedLabel));
                  }
                  if (!option && Number.isInteger(index) && index >= 0 && index < options.length) option = options[index];
                  if (!option) return JSON.stringify({ ok: false, message: 'Matching option was not found.' });
                  select.value = option.value;
                  option.selected = true;
                  select.dispatchEvent(new Event('input', { bubbles: true }));
                  select.dispatchEvent(new Event('change', { bubbles: true }));
                  return JSON.stringify({
                    ok: true,
                    message: 'Option selected.',
                    selector,
                    selectedIndex: select.selectedIndex,
                    value: select.value,
                    text: (option.label || option.text || '').trim()
                  });
                })();
            """.trimIndent(),
            successMessage = "Option selected.",
            callback = callback,
        )
    }

    private fun extract(
        selector: String?,
        prompt: String?,
        maxLength: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safeMaxLength = maxLength.coerceIn(256, 16000)
        runActionJson(
            script = """
                (() => {
                  const selector = ${(selector?.trim().orEmpty()).jsQuote()};
                  const prompt = ${(prompt?.trim().orEmpty()).jsQuote()};
                  const maxLength = $safeMaxLength;
                  const target = selector ? document.querySelector(selector) : document.body;
                  if (!target) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  const text = (target.innerText || target.textContent || '').trim().slice(0, maxLength);
                  const html = (target.innerHTML || '').trim().slice(0, maxLength);
                  return JSON.stringify({
                    ok: true,
                    selector: selector || null,
                    prompt: prompt || null,
                    text,
                    html,
                    tag: target.tagName || 'BODY',
                    links: Array.from(target.querySelectorAll('a[href]')).slice(0, 12).map((item) => ({
                      href: item.href || '',
                      text: (item.innerText || item.textContent || '').trim().slice(0, 160)
                    }))
                  });
                })();
            """.trimIndent(),
            successMessage = "Page content extracted.",
            callback = callback,
        )
    }

    private fun listLinks(
        filter: String?,
        maxItems: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safeMaxItems = maxItems.coerceIn(1, 40)
        runActionJson(
            script = """
                (() => {
                  const filter = ${(filter?.trim()?.lowercase().orEmpty()).jsQuote()};
                  const maxItems = $safeMaxItems;
                  const links = Array.from(document.querySelectorAll('a[href]'))
                    .map((item, index) => {
                      const text = (item.innerText || item.textContent || '').trim().slice(0, 160);
                      const href = item.href || '';
                      const aria = (item.getAttribute('aria-label') || '').trim();
                      return { index, text, href, aria };
                    })
                    .filter((item) => {
                      if (!filter) return true;
                      const haystack = `${'$'}{item.text} ${'$'}{item.href} ${'$'}{item.aria}`.toLowerCase();
                      return haystack.includes(filter);
                    })
                    .slice(0, maxItems);
                  return JSON.stringify({ ok: true, count: links.length, items: links });
                })();
            """.trimIndent(),
            successMessage = "Link list extracted.",
            callback = callback,
        )
    }

    private fun listInteractables(
        filter: String?,
        maxItems: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safeMaxItems = maxItems.coerceIn(1, 60)
        runActionJson(
            script = """
                (() => {
                  const filter = ${(filter?.trim()?.lowercase().orEmpty()).jsQuote()};
                  const maxItems = $safeMaxItems;
                  const cssEscape = (value) => {
                    if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(value);
                    return String(value).replace(/["\\]/g, (match) => '\\' + match);
                  };
                  const selectorFor = (el) => {
                    if (el.id) return `#${'$'}{cssEscape(el.id)}`;
                    const dataTestId = el.getAttribute('data-testid');
                    if (dataTestId) return `[data-testid="${'$'}{cssEscape(dataTestId)}"]`;
                    const name = el.getAttribute('name');
                    if (name) return `${'$'}{el.tagName.toLowerCase()}[name="${'$'}{cssEscape(name)}"]`;
                    const aria = el.getAttribute('aria-label');
                    if (aria) return `${'$'}{el.tagName.toLowerCase()}[aria-label="${'$'}{cssEscape(aria)}"]`;
                    const classes = Array.from(el.classList || []).filter(Boolean).slice(0, 2);
                    if (classes.length > 0) return `${'$'}{el.tagName.toLowerCase()}.${'$'}{classes.map(cssEscape).join('.')}`;
                    return el.tagName.toLowerCase();
                  };
                  const isVisible = (el) => {
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
                  };
                  const items = Array.from(document.querySelectorAll('a,button,input,textarea,select,[role="button"],[contenteditable="true"]'))
                    .filter(isVisible)
                    .map((el, index) => ({
                      index,
                      tag: el.tagName.toLowerCase(),
                      role: (el.getAttribute('role') || '').trim(),
                      type: (el.getAttribute('type') || '').trim(),
                      text: (el.innerText || el.textContent || el.value || '').trim().slice(0, 160),
                      aria: (el.getAttribute('aria-label') || '').trim(),
                      placeholder: (el.getAttribute('placeholder') || '').trim(),
                      selector: selectorFor(el)
                    }))
                    .filter((item) => {
                      if (!filter) return true;
                      const haystack = `${'$'}{item.tag} ${'$'}{item.role} ${'$'}{item.type} ${'$'}{item.text} ${'$'}{item.aria} ${'$'}{item.placeholder} ${'$'}{item.selector}`.toLowerCase();
                      return haystack.includes(filter);
                    })
                    .slice(0, maxItems);
                  return JSON.stringify({ ok: true, count: items.length, items });
                })();
            """.trimIndent(),
            successMessage = "Interactable elements extracted.",
            callback = callback,
        )
    }

    private fun listOverlays(
        maxItems: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safeMaxItems = maxItems.coerceIn(1, 80)
        runActionJson(
            script = """
                (() => {
                  const visible = (element) => {
                    const rect = element.getBoundingClientRect();
                    const style = getComputedStyle(element);
                    return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
                  };
                  const candidates = Array.from(document.querySelectorAll('[role="dialog"], [role="menu"], [role="listbox"], [aria-modal="true"], [data-radix-popper-content-wrapper], [data-radix-portal], body *'))
                    .filter((element) => visible(element))
                    .filter((element) => {
                      const style = getComputedStyle(element);
                      return ['fixed', 'absolute'].includes(style.position) || ['dialog', 'menu', 'listbox'].includes(element.getAttribute('role') || '') || element.getAttribute('aria-modal') === 'true';
                    })
                    .map((element) => {
                      const rect = element.getBoundingClientRect();
                      const style = getComputedStyle(element);
                      return { tag: element.tagName || '', role: element.getAttribute('role') || '', ariaLabel: element.getAttribute('aria-label') || '', text: (element.innerText || element.textContent || '').trim().slice(0, 240), zIndex: style.zIndex || 'auto', rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) } };
                    })
                    .sort((a, b) => (Number.parseInt(b.zIndex, 10) || 0) - (Number.parseInt(a.zIndex, 10) || 0))
                    .slice(0, $safeMaxItems);
                  return JSON.stringify({ ok: true, overlays: candidates });
                })();
            """.trimIndent(),
            successMessage = "Visible overlays listed.",
            callback = callback,
        )
    }

    private fun clickAt(
        x: Double,
        y: Double,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        if (!x.isFinite() || !y.isFinite() || x < 0 || y < 0) {
            callback(snapshot(ok = false, message = "Coordinates must be finite non-negative viewport values."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const x = ${x.toJsNumber()};
                  const y = ${y.toJsNumber()};
                  const element = document.elementFromPoint(x, y);
                  if (!element) return JSON.stringify({ ok: false, message: 'No element exists at the requested viewport coordinates.' });
                  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                  if (typeof element.focus === 'function') element.focus();
                  for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
                    element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
                  }
                  const rect = element.getBoundingClientRect();
                  return JSON.stringify({ ok: true, message: 'Clicked element at viewport coordinates.', tag: element.tagName || '', text: (element.innerText || element.textContent || element.getAttribute('aria-label') || '').trim().slice(0, 160), rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) } });
                })();
            """.trimIndent(),
            successMessage = "Coordinate click completed.",
            callback = callback,
        )
    }

    private fun highlight(selector: String, callback: (Map<String, Any?>) -> Unit) {
        if (selector.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The selector argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const selector = ${selector.jsQuote()};
                  const element = document.querySelector(selector);
                  if (!element) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  const previousOutline = element.style.outline || '';
                  const previousOffset = element.style.outlineOffset || '';
                  const previousTransition = element.style.transition || '';
                  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                  element.style.transition = 'outline 120ms ease';
                  element.style.outline = '3px solid #dc2626';
                  element.style.outlineOffset = '2px';
                  setTimeout(() => {
                    element.style.outline = previousOutline;
                    element.style.outlineOffset = previousOffset;
                    element.style.transition = previousTransition;
                  }, 2200);
                  return JSON.stringify({
                    ok: true,
                    message: 'Element highlighted.',
                    tag: element.tagName || '',
                    text: (element.innerText || element.textContent || element.value || '').trim().slice(0, 200)
                  });
                })();
            """.trimIndent(),
            successMessage = "Element highlighted.",
            callback = callback,
        )
    }

    private fun captureSnapshot(
        selector: String?,
        maxLength: Int,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val safeMaxLength = maxLength.coerceIn(512, 32000)
        runActionJson(
            script = """
                (() => {
                  const selector = ${(selector?.trim().orEmpty()).jsQuote()};
                  const maxLength = $safeMaxLength;
                  const target = selector ? document.querySelector(selector) : document.body;
                  if (!target) return JSON.stringify({ ok: false, message: `Selector not found: ${'$'}{selector}` });
                  const text = (target.innerText || target.textContent || '').trim().slice(0, maxLength);
                  const html = (target.innerHTML || '').trim().slice(0, maxLength);
                  const links = Array.from(target.querySelectorAll('a[href]')).slice(0, 20).map((item) => ({
                    href: item.href || '',
                    text: (item.innerText || item.textContent || '').trim().slice(0, 160)
                  }));
                  return JSON.stringify({
                    ok: true,
                    title: document.title || '',
                    url: location.href || '',
                    selector: selector || null,
                    text,
                    html,
                    links
                  });
                })();
            """.trimIndent(),
            successMessage = "Snapshot captured.",
            callback = callback,
        )
    }

    private fun eval(script: String, callback: (Map<String, Any?>) -> Unit) {
        if (script.trim().isEmpty()) {
            callback(snapshot(ok = false, message = "The script argument cannot be empty."))
            return
        }
        runActionJson(
            script = """
                (() => {
                  const result = (() => {
                    $script
                  })();
                  return JSON.stringify({
                    ok: true,
                    result
                  });
                })();
            """.trimIndent(),
            successMessage = "Script executed.",
            callback = callback,
        )
    }

    private fun runActionJson(
        script: String,
        successMessage: String,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        val tab = activeTabOrNull() ?: return callback(snapshot(ok = false, message = "Browser page is unavailable."))
        runJsonScript(tab, script) { decoded ->
            if (decoded == null) {
                callback(snapshot(ok = false, message = "Failed to run the browser action in WebView."))
                return@runJsonScript
            }
            callback(
                snapshot(
                    ok = decoded.optBoolean("ok", true),
                    message = decoded.optString("message").ifBlank { successMessage },
                    extra = mapOf("actionResult" to decoded.toMap()),
                ),
            )
        }
    }

    private fun runJsonScript(
        tab: NativeBrowserTab,
        script: String,
        callback: (JSONObject?) -> Unit,
    ) {
        tab.webView.evaluateJavascript(script) { raw ->
            callback(raw.toDecodedJsonObject())
        }
    }

    private fun pollJsonScript(
        tab: NativeBrowserTab,
        timeoutMs: Int,
        intervalMs: Int,
        script: String,
        predicate: (JSONObject) -> Boolean,
        onSuccess: (JSONObject) -> Unit,
        onTimeout: () -> Unit,
    ) {
        val deadline = System.currentTimeMillis() + timeoutMs
        fun attempt() {
            runJsonScript(tab, script) { decoded ->
                if (decoded != null && predicate(decoded)) {
                    onSuccess(decoded)
                    return@runJsonScript
                }
                if (System.currentTimeMillis() >= deadline) {
                    onTimeout()
                    return@runJsonScript
                }
                mainHandler.postDelayed({ attempt() }, intervalMs.toLong())
            }
        }
        attempt()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val MENU_RECENT_ACTIONS = 1001
        private const val MENU_INSPECTOR = 1002
        private const val MENU_SCRIPTS = 1003
        private const val MENU_SNAPSHOT = 1004
        private const val MENU_COPY_URL = 1005
        private const val MENU_WELCOME = 1006
        private const val MENU_SELF_TEST = 1007
        private const val PREF_AUTOMATION_SCRIPTS = "flutter.browser_automation_scripts_json"
        private const val PREF_USER_SCRIPTS = "flutter.browser_user_scripts_v1"
        private val RUNNABLE_SCRIPT_ACTIONS = setOf(
            "open",
            "back",
            "forward",
            "reload",
            "click",
            "type",
            "paste",
            "wait_for_text",
            "wait_for_selector",
            "scroll",
            "press_key",
            "select_option",
            "extract",
            "list_links",
            "list_interactables",
            "highlight",
            "capture_snapshot",
        )
        private val TOOL_ACTION_ALIASES = mapOf(
            "browser_open" to "open",
            "browser_back" to "back",
            "browser_forward" to "forward",
            "browser_reload" to "reload",
            "browser_click" to "click",
            "browser_type" to "type",
            "browser_paste" to "paste",
            "browser_wait_for_text" to "wait_for_text",
            "browser_wait_for_selector" to "wait_for_selector",
            "browser_scroll" to "scroll",
            "browser_press_key" to "press_key",
            "browser_select_option" to "select_option",
            "browser_extract" to "extract",
            "browser_list_links" to "list_links",
            "browser_list_interactables" to "list_interactables",
            "browser_highlight" to "highlight",
            "browser_capture_snapshot" to "capture_snapshot",
        )
        private const val WELCOME_HTML = """
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>Codex 浏览器自动化控制</title>
    <style>
      :root { color-scheme: dark; }
      html, body { margin: 0; padding: 0; background: #050505; color: #f5f5f5; font-family: sans-serif; min-height: 100%; }
      body { box-sizing: border-box; padding: 18px; }
      main { width: min(92vw, 560px); margin: 0 auto; }
      .panel {
        border: 1px solid rgba(220,38,38,0.26);
        border-radius: 20px;
        background:
          radial-gradient(circle at top right, rgba(220,38,38,0.18), transparent 34%),
          linear-gradient(180deg, #161616 0%, #0d0d0d 100%);
        box-shadow: 0 24px 60px rgba(0,0,0,0.35);
        padding: 20px;
        box-sizing: border-box;
      }
      h1 { margin: 0 0 8px; font-size: 21px; line-height: 1.25; }
      h2 { margin: 20px 0 8px; font-size: 14px; color: #ffffff; }
      p, li { line-height: 1.6; color: #d4d4d4; font-size: 14px; }
      p { margin: 0 0 12px; }
      ul { margin: 0; padding-left: 18px; }
      code { display: inline-block; max-width: 100%; padding: 2px 7px; border-radius: 999px; background: rgba(255,255,255,0.08); color: #ffffff; overflow-wrap: anywhere; }
      .status {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        margin: 0 0 14px;
        padding: 6px 10px;
        border: 1px solid rgba(220,38,38,0.34);
        border-radius: 999px;
        color: #fecaca;
        background: rgba(220,38,38,0.12);
        font-size: 12px;
        font-weight: 700;
      }
      .dot { width: 7px; height: 7px; border-radius: 999px; background: #dc2626; }
    </style>
  </head>
  <body>
    <main>
      <section class="panel">
        <div class="status"><span class="dot"></span>浏览器自动化已就绪</div>
        <h1>Codex 浏览器自动化控制</h1>
        <p>这个浏览器用于打开你指定的网页，让 Codex 通过浏览器工具执行访问、点击、输入、滚动、选择、等待元素、提取页面内容和截图快照等操作。</p>
        <h2>使用方式</h2>
        <ul>
          <li>在终端里告诉 Codex 目标网址和要完成的任务。</li>
          <li>需要登录、搜索、填写表单或读取页面内容时，让 Codex 使用 <code>browser-operator</code>。</li>
          <li>你也可以在上方地址栏手动输入网址，当前页面会被 Codex 接管。</li>
          <li>浏览器默认请求手机页面；需要桌面页面时，可以切换到 <code>电脑</code>。</li>
        </ul>
      </section>
    </main>
  </body>
</html>
"""

        private const val SELF_TEST_HTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenClaw Browser Self Test</title>
    <style>
      :root { color-scheme: dark; }
      html, body { margin: 0; min-height: 100%; background: #0a0a0a; color: #f7f7f7; font-family: sans-serif; }
      body { display: grid; place-items: center; }
      main {
        width: min(88vw, 420px);
        border: 1px solid rgba(220,38,38,0.28);
        border-radius: 20px;
        padding: 22px;
        background:
          radial-gradient(circle at top right, rgba(220,38,38,0.18), transparent 30%),
          linear-gradient(180deg, #161616 0%, #0d0d0d 100%);
        box-shadow: 0 24px 60px rgba(0,0,0,0.35);
      }
      h1 { margin: 0 0 8px; font-size: 20px; }
      p { margin: 0; color: #d6d6d6; line-height: 1.5; }
    </style>
    <script>
      window.__openclawBrowserSelfTest = 'ready';
    </script>
  </head>
  <body>
    <main data-openclaw-self-test="ready">
      <h1>Browser self-test ready</h1>
      <p>The embedded browser loaded local HTML and JavaScript is available.</p>
    </main>
  </body>
</html>
"""
    }
}

private fun Map<String, Any?>.stringValue(key: String, fallback: String = ""): String =
    this[key]?.toString()?.trim().orEmpty().ifEmpty { fallback }

private fun Map<String, Any?>.nullableStringValue(key: String): String? =
    this[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }

private fun Map<String, Any?>.booleanValue(key: String, fallback: Boolean = false): Boolean =
    when (val value = this[key]) {
        is Boolean -> value
        is String -> value.equals("true", ignoreCase = true)
        else -> fallback
    }

private fun Map<String, Any?>.intValue(key: String, fallback: Int): Int =
    when (val value = this[key]) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull() ?: fallback
        else -> fallback
    }

private fun Map<String, Any?>.nullableIntValue(key: String): Int? =
    when (val value = this[key]) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }

private fun Map<String, Any?>.doubleValue(key: String): Double =
    when (val value = this[key]) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull() ?: Double.NaN
        else -> Double.NaN
    }

private fun String.jsQuote(): String = JSONObject.quote(this)

private fun Boolean.jsBool(): String = if (this) "true" else "false"

private fun Double.toJsNumber(): String =
    if (abs(this % 1.0) < 0.0000001) this.toInt().toString() else toString()

private fun String?.toDecodedJsonObject(): JSONObject? {
    val text = this?.trim().orEmpty()
    if (text.isEmpty() || text == "null" || text == "undefined") {
        return null
    }
    val decoded = try {
        JSONTokener(text).nextValue()
    } catch (_: Exception) {
        text
    }
    val normalized = when (decoded) {
        null, JSONObject.NULL -> return null
        is String -> decoded
        else -> decoded.toString()
    }
    return try {
        JSONObject(normalized)
    } catch (_: Exception) {
        null
    }
}

private fun JSONObject.toMap(): Map<String, Any?> {
    val result = linkedMapOf<String, Any?>()
    keys().forEach { key ->
        result[key] = when (val value = opt(key)) {
            is JSONObject -> value.toMap()
            is JSONArray -> value.toList()
            JSONObject.NULL -> null
            else -> value
        }
    }
    return result
}

private fun JSONArray.toList(): List<Any?> {
    val result = mutableListOf<Any?>()
    for (index in 0 until length()) {
        result += when (val value = opt(index)) {
            is JSONObject -> value.toMap()
            is JSONArray -> value.toList()
            JSONObject.NULL -> null
            else -> value
        }
    }
    return result
}

private fun JSONArray.toStringList(): List<String> {
    val result = mutableListOf<String>()
    for (index in 0 until length()) {
        val value = opt(index)?.toString()?.trim().orEmpty()
        if (value.isNotEmpty()) {
            result += value
        }
    }
    return result
}

private fun Map<String, Any?>.resolveScriptVariables(
    variables: Map<String, String>,
): Map<String, Any?> = entries.associate { (key, value) ->
    key to resolveScriptValue(value, variables)
}

private fun resolveScriptValue(
    value: Any?,
    variables: Map<String, String>,
): Any? = when (value) {
    null -> null
    is String -> variables.entries.fold(value) { resolved, (name, replacement) ->
        resolved.replace("{{${name}}}", replacement)
    }
    is Map<*, *> -> value.entries.associate { (key, nestedValue) ->
        key.toString() to resolveScriptValue(nestedValue, variables)
    }
    is List<*> -> value.map { item -> resolveScriptValue(item, variables) }
    else -> value
}
