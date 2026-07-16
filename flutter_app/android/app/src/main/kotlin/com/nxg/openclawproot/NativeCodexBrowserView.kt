package com.agent.cyx

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
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
import android.widget.LinearLayout
import android.widget.TextView
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

@SuppressLint("SetJavaScriptEnabled")
class NativeCodexBrowserView(
    context: Context,
) : FrameLayout(context), NativeBrowserAutomationController {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tabs = mutableListOf<NativeBrowserTab>()
    private val tabStrip = LinearLayout(context)
    private val webViewContainer = FrameLayout(context)
    private val addressInput = EditText(context)
    private val bridgeStatusView = TextView(context)
    private val uaButton = TextView(context)
    private var nextTabId = 1
    private var activeTabIndex = 0

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
            when (action) {
                "get_state" -> callback(snapshot(message = "Browser state loaded."))
                "self_test" -> runSelfTest(callback)
                "health_check" -> runHealthCheck(
                    quietWindowMs = payload.intValue("quietWindowMs", 500),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = callback,
                )
                "open" -> openUrl(payload.stringValue("url"), callback)
                "back" -> goBack(callback)
                "forward" -> goForward(callback)
                "reload" -> reloadPage(callback)
                "tab_list" -> callback(snapshot(message = "Browser tabs loaded."))
                "tab_new" -> openNewTab(payload.nullableStringValue("url"), callback)
                "tab_switch" -> switchTab(payload.intValue("id", 0), callback)
                "tab_close" -> closeTab(payload.nullableIntValue("id"), callback)
                "set_ua" -> setUserAgent(payload.stringValue("mode"), callback)
                "click" -> click(payload.stringValue("selector"), callback)
                "type" -> typeText(
                    selector = payload.stringValue("selector"),
                    text = payload.stringValue("text"),
                    submit = payload.booleanValue("submit"),
                    callback = callback,
                )
                "paste" -> pasteText(
                    selector = payload.stringValue("selector"),
                    text = payload.stringValue("text"),
                    submit = payload.booleanValue("submit"),
                    callback = callback,
                )
                "wait_for_resource" -> waitForResource(
                    pattern = payload.stringValue("pattern"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = callback,
                )
                "list_overlays" -> listOverlays(
                    maxItems = payload.intValue("maxItems", 24),
                    callback = callback,
                )
                "click_at" -> clickAt(
                    x = payload.doubleValue("x"),
                    y = payload.doubleValue("y"),
                    callback = callback,
                )
                "reset_tab" -> resetTab(payload.nullableStringValue("url"), callback)
                "wait_for_text" -> waitForText(
                    text = payload.stringValue("text"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    callback = callback,
                )
                "wait_for_selector" -> waitForSelector(
                    selector = payload.stringValue("selector"),
                    timeoutMs = payload.intValue("timeoutMs", 10000),
                    visible = payload.booleanValue("visible", true),
                    callback = callback,
                )
                "scroll" -> scrollPage(
                    selector = payload.nullableStringValue("selector"),
                    direction = payload.stringValue("direction", "down"),
                    pixels = payload.intValue("pixels", 700),
                    callback = callback,
                )
                "press_key" -> pressKey(
                    selector = payload.nullableStringValue("selector"),
                    key = payload.stringValue("key"),
                    callback = callback,
                )
                "select_option" -> selectOption(
                    selector = payload.stringValue("selector"),
                    value = payload.nullableStringValue("value"),
                    label = payload.nullableStringValue("label"),
                    index = payload.nullableIntValue("index"),
                    callback = callback,
                )
                "extract" -> extract(
                    selector = payload.nullableStringValue("selector"),
                    prompt = payload.nullableStringValue("prompt"),
                    maxLength = payload.intValue("maxLength", 4000),
                    callback = callback,
                )
                "list_links" -> listLinks(
                    filter = payload.nullableStringValue("filter"),
                    maxItems = payload.intValue("maxItems", 12),
                    callback = callback,
                )
                "list_interactables" -> listInteractables(
                    filter = payload.nullableStringValue("filter"),
                    maxItems = payload.intValue("maxItems", 16),
                    callback = callback,
                )
                "highlight" -> highlight(payload.stringValue("selector"), callback)
                "capture_snapshot" -> captureSnapshot(
                    selector = payload.nullableStringValue("selector"),
                    maxLength = payload.intValue("maxLength", 8000),
                    callback = callback,
                )
                "eval" -> eval(payload.stringValue("script"), callback)
                else -> callback(
                    snapshot(
                        ok = false,
                        message = "Unsupported native browser action: $action",
                    ),
                )
            }
        }
    }

    private fun setupLayout() {
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
        }

        bridgeStatusView.apply {
            setTextColor(Color.parseColor("#B7F7CC"))
            textSize = 11f
            setPadding(dp(10), dp(8), dp(10), dp(2))
            text = "浏览器自动化已连接"
        }

        val tabScroller = HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            setBackgroundColor(Color.parseColor("#090909"))
            addView(
                tabStrip.apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(8), dp(4), dp(8), dp(4))
                },
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

        val addressRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setBackgroundColor(Color.parseColor("#111111"))
        }

        addressRow.addView(createActionButton("←") { executeAction("back", emptyMap()) {} })
        addressRow.addView(createActionButton("→") { executeAction("forward", emptyMap()) {} })
        addressRow.addView(createActionButton("↻") { executeAction("reload", emptyMap()) {} })

        addressInput.apply {
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#8A8A8A"))
            hint = "输入网址或本地地址"
            background = actionButtonDrawable(Color.parseColor("#161616"))
            typeface = Typeface.MONOSPACE
            textSize = 12f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setSingleLine(true)
            setOnEditorActionListener { _, _, _ ->
                openUrl(addressInput.text?.toString().orEmpty()) {}
                true
            }
        }
        addressRow.addView(
            addressInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(6)
                marginEnd = dp(6)
            },
        )

        uaButton.apply {
            minimumWidth = dp(48)
        }
        addressRow.addView(
            uaButton.also {
                it.setOnClickListener {
                    val nextMode = if (activeTabOrNull()?.userAgentMode == NativeBrowserUserAgentMode.DESKTOP) {
                        NativeBrowserUserAgentMode.MOBILE
                    } else {
                        NativeBrowserUserAgentMode.DESKTOP
                    }
                    executeAction("set_ua", mapOf("mode" to nextMode.value)) {}
                }
            },
        )
        addressRow.addView(createActionButton("打开") {
            openUrl(addressInput.text?.toString().orEmpty()) {}
        })

        webViewContainer.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f,
        )

        root.addView(bridgeStatusView)
        root.addView(tabScroller)
        root.addView(addressRow)
        root.addView(webViewContainer)
        addView(
            root,
            LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun createActionButton(label: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            text = label
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            textSize = 12f
            typeface = Typeface.MONOSPACE
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = actionButtonDrawable(Color.parseColor("#161616"))
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

    private fun actionButtonDrawable(color: Int) =
        android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = dp(7).toFloat()
            setColor(color)
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
        } else {
            "浏览器自动化已连接 · ${tab.title.ifBlank { "Browser" }}"
        }
        uaButton.text = tab.userAgentMode.label
        uaButton.setTextColor(Color.WHITE)
        uaButton.gravity = Gravity.CENTER
        uaButton.textSize = 12f
        uaButton.typeface = Typeface.MONOSPACE
        uaButton.setPadding(dp(12), dp(10), dp(12), dp(10))
        uaButton.background = actionButtonDrawable(Color.parseColor("#161616"))
        renderTabStrip()
    }

    private fun renderTabStrip() {
        tabStrip.removeAllViews()
        tabs.forEachIndexed { index, tab ->
            tabStrip.addView(
                TextView(context).apply {
                    text = buildString {
                        append(if (index == activeTabIndex) "● " else "○ ")
                        append(tab.title.ifBlank { "Browser ${index + 1}" }.take(24))
                    }
                    setTextColor(Color.WHITE)
                    textSize = 11f
                    typeface = Typeface.MONOSPACE
                    setPadding(dp(12), dp(8), dp(12), dp(8))
                    background = actionButtonDrawable(
                        if (index == activeTabIndex) Color.parseColor("#2A2A2A")
                        else Color.parseColor("#141414"),
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
        tabStrip.addView(createActionButton("+") {
            executeAction("tab_new", emptyMap()) {}
        })
        tabStrip.addView(createActionButton("×") {
            executeAction("tab_close", emptyMap()) {}
        })
    }

    private fun activeIndexSafeSet(index: Int) {
        if (index !in tabs.indices || index == activeTabIndex) {
            return
        }
        activeTabIndex = index
        attachActiveTab()
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
      .panel { border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; background: linear-gradient(180deg, #101010 0%, #070707 100%); padding: 18px; box-sizing: border-box; }
      h1 { margin: 0 0 8px; font-size: 21px; line-height: 1.25; }
      h2 { margin: 20px 0 8px; font-size: 14px; color: #ffffff; }
      p, li { line-height: 1.6; color: #d4d4d4; font-size: 14px; }
      p { margin: 0 0 12px; }
      ul { margin: 0; padding-left: 18px; }
      code { display: inline-block; max-width: 100%; padding: 2px 7px; border-radius: 999px; background: rgba(255,255,255,0.08); color: #ffffff; overflow-wrap: anywhere; }
      .status { display: inline-flex; align-items: center; gap: 6px; margin: 0 0 14px; padding: 5px 9px; border: 1px solid rgba(34,197,94,0.42); border-radius: 999px; color: #bbf7d0; background: rgba(34,197,94,0.1); font-size: 12px; font-weight: 700; }
      .dot { width: 7px; height: 7px; border-radius: 999px; background: #22c55e; }
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
      main { width: min(88vw, 420px); border: 1px solid rgba(255,255,255,0.12); border-radius: 8px; padding: 20px; }
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
