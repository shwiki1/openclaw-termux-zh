package com.agent.cyx

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.style.ForegroundColorSpan
import android.util.LruCache
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerControlView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Enumeration
import java.util.LinkedHashSet
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class FloatingFileManagerService : Service() {
    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val requestIdGenerator = AtomicInteger(0)
    private val tabIdGenerator = AtomicInteger(0)
    private val thumbnailCache = object : LruCache<String, Bitmap>(24) {}
    private val prefs by lazy { getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
    private val favoriteDirs = linkedSetOf<String>()
    private val recentDirs = mutableListOf<String>()

    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var panelRoot: LinearLayout? = null
    private var overlayFocusable = false

    private val tabs = mutableListOf<FileTab>()
    private var activeTabId: Int = -1

    private var currentPreviewFile: File? = null
    private var currentPlayer: ExoPlayer? = null
    private var currentTextEditor: CodeEditorEditText? = null
    private var previewing = false

    private var viewMode = ViewMode.LIST
    private var sortMode = SortMode.NAME
    private var showHidden = false
    private var selectionMode = false
    private val selectedPaths = LinkedHashSet<String>()
    private var clipboard: ClipboardState? = null

    private var titleView: TextView? = null
    private var backButton: TextView? = null
    private var saveButton: TextView? = null
    private var openButton: TextView? = null
    private var shareButton: TextView? = null
    private var extractButton: TextView? = null
    private var minimizeButton: TextView? = null
    private var tabsScroll: HorizontalScrollView? = null
    private var tabsRow: LinearLayout? = null
    private var quickRootsScroll: HorizontalScrollView? = null
    private var quickRootsRow: LinearLayout? = null
    private var breadcrumbScroll: HorizontalScrollView? = null
    private var breadcrumbRow: LinearLayout? = null
    private var controlBarScroll: HorizontalScrollView? = null
    private var controlBarRow: LinearLayout? = null
    private var contentContainer: FrameLayout? = null
    private var operationContainer: LinearLayout? = null
    private var operationProgressBar: ProgressBar? = null
    private var operationView: TextView? = null
    private var statusView: TextView? = null
    private var recyclerView: RecyclerView? = null
    private var loadingView: TextView? = null
    private var fileAdapter: FileListAdapter? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        restoreDirectoryCollections()
        ensureDefaultTabs()
        startForeground(NOTIFICATION_ID, buildNotification())
        showMinimizedBubble()
    }

    override fun onDestroy() {
        releasePlayer()
        worker.shutdownNow()
        rootView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        panelRoot = null
        rootView = null
        running = false
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val channelId = "floating_file_manager"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Floating File Manager",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentTitle("Floating file manager")
            .setContentText("Tap the floating button to browse shared and app-private storage.")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun overlayType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun baseParams(width: Int, height: Int): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            width,
            height,
            overlayType(),
            buildWindowFlags(overlayFocusable),
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 140
        }
    }

    private fun buildWindowFlags(focusable: Boolean): Int {
        var flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        if (!focusable) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }
        return flags
    }

    private fun updateOverlayFocusability(focusable: Boolean, inputTarget: View? = null) {
        overlayFocusable = focusable
        val lp = params ?: return
        val nextFlags = buildWindowFlags(focusable)
        if (lp.flags != nextFlags) {
            lp.flags = nextFlags
            rootView?.let { windowManager.updateViewLayout(it, lp) }
        }
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (focusable) {
            panelRoot?.isFocusableInTouchMode = true
            panelRoot?.requestFocus()
            inputTarget?.post {
                inputTarget.requestFocus()
                imm.showSoftInput(inputTarget, InputMethodManager.SHOW_IMPLICIT)
            }
        } else {
            rootView?.clearFocus()
            val token = currentTextEditor?.windowToken ?: panelRoot?.windowToken ?: rootView?.windowToken
            token?.let { imm.hideSoftInputFromWindow(it, 0) }
        }
    }

    private fun replaceView(view: View, width: Int, height: Int) {
        val oldParams = params
        rootView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        val nextParams = baseParams(width, height)
        if (oldParams != null) {
            nextParams.x = oldParams.x
            nextParams.y = oldParams.y
        }
        params = nextParams
        rootView = view
        windowManager.addView(view, nextParams)
    }

    private fun ensureDefaultTabs() {
        if (tabs.isNotEmpty()) {
            return
        }
        val shared = createTab(defaultSharedRoot(), pinned = true)
        createTab(appPrivateRoot(), pinned = true)
        activeTabId = shared.id
    }

    private fun createTab(initialDir: File, pinned: Boolean = false): FileTab {
        val safeDir = if (initialDir.exists()) initialDir else defaultSharedRoot()
        val tab = FileTab(
            id = tabIdGenerator.incrementAndGet(),
            title = shortDirLabel(safeDir),
            currentDir = safeDir,
            pinned = pinned,
        )
        tabs.add(tab)
        return tab
    }

    private fun activeTab(): FileTab {
        ensureDefaultTabs()
        return tabs.firstOrNull { it.id == activeTabId } ?: tabs.first().also { activeTabId = it.id }
    }

    private fun findTab(id: Int): FileTab? = tabs.firstOrNull { it.id == id }

    private fun defaultSharedRoot(): File = Environment.getExternalStorageDirectory()

    private fun appPrivateRoot(): File = filesDir.parentFile ?: filesDir

    private fun setActiveDir(dir: File, keepSelection: Boolean = false) {
        val tab = activeTab()
        tab.currentDir = dir
        tab.title = shortDirLabel(dir)
        rememberRecentDir(dir)
        if (!keepSelection) {
            clearSelection()
        }
    }

    private fun showMinimizedBubble() {
        releasePlayer()
        currentTextEditor = null
        previewing = false
        updateOverlayFocusability(false)
        clearSelection()
        val bubble = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = rounded(0xEE161616.toInt(), 18, 0, 0)
            setOnClickListener { showFilePanel() }
        }
        bubble.addView(TextView(this).apply {
            text = "文件"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
        })
        attachDrag(bubble)
        replaceView(
            bubble,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun showFilePanel() {
        releasePlayer()
        currentTextEditor = null
        previewing = false
        currentPreviewFile = null
        updateOverlayFocusability(false)
        ensureDefaultTabs()
        ensurePanelBuilt()
        panelRoot?.let { panel ->
            if (rootView !== panel) {
                replaceView(panel, panelWidth(), panelHeight())
            }
        }
        bindPanelScaffold()
        renderDirectoryState(forceReload = activeTab().entries.isEmpty())
    }

    private fun ensurePanelBuilt() {
        if (panelRoot != null) {
            return
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(8))
            background = rounded(0xF2131313.toInt(), 18, 1, 0xFF343434.toInt())
            isFocusableInTouchMode = true
            setOnKeyListener { _, keyCode, event ->
                if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    if (previewing) {
                        closePreview()
                    } else {
                        showMinimizedBubble()
                    }
                    true
                } else {
                    false
                }
            }
        }

        panel.addView(buildToolbar())

        val tabScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 0, 0, dp(8))
            }
            tabsRow = row
            addView(row)
        }
        tabsScroll = tabScroll
        panel.addView(tabScroll)

        val rootsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 0, 0, dp(8))
            }
            quickRootsRow = row
            addView(row)
        }
        quickRootsScroll = rootsScroll
        panel.addView(rootsScroll)

        val crumbScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 0, 0, dp(8))
            }
            breadcrumbRow = row
            addView(row)
        }
        breadcrumbScroll = crumbScroll
        panel.addView(crumbScroll)

        val controlsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 0, 0, dp(8))
            }
            controlBarRow = row
            addView(row)
        }
        controlBarScroll = controlsScroll
        panel.addView(controlsScroll)

        val content = FrameLayout(this).apply {
            background = rounded(Color.BLACK, 14, 1, 0xFF2F2F2F.toInt())
        }
        contentContainer = content
        panel.addView(
            content,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        val operationBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(4), dp(8), dp(4), 0)
        }
        val operationText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 11f
            maxLines = 3
        }
        val operationBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progress = 0
            progressTintList = ColorStateList.valueOf(0xFF6EA7FF.toInt())
            progressBackgroundTintList = ColorStateList.valueOf(0xFF303030.toInt())
        }
        operationBox.addView(operationText)
        operationBox.addView(
            operationBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(6)
            },
        )
        operationContainer = operationBox
        operationProgressBar = operationBar
        operationView = operationText
        panel.addView(operationBox)

        val status = TextView(this).apply {
            setTextColor(0xFF8F8F8F.toInt())
            textSize = 10f
            maxLines = 3
            setPadding(dp(4), dp(6), dp(4), 0)
        }
        statusView = status
        panel.addView(status)

        loadingView = TextView(this).apply {
            gravity = Gravity.CENTER
            setTextColor(0xFFB8B8B8.toInt())
            textSize = 13f
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        recyclerView = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(context)
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            itemAnimator = null
            setHasFixedSize(true)
            setPadding(dp(6), dp(6), dp(6), dp(6))
            clipToPadding = false
        }
        fileAdapter = FileListAdapter().also { recyclerView?.adapter = it }

        panelRoot = panel
    }

    private fun buildToolbar(): LinearLayout {
        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(2), dp(2), dp(8))
        }
        attachDrag(toolbar)

        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        }
        titleView = title
        toolbar.addView(
            title,
            LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            ),
        )

        val back = tinyButton("上级") {
            if (previewing) {
                closePreview()
            } else {
                goParent()
            }
        }
        val save = tinyButton("保存") { saveCurrentTextFile() }
        val open = tinyButton("打开") { currentPreviewFile?.let { openExternal(it) } }
        val share = tinyButton("分享") { currentPreviewFile?.let { shareFile(it) } }
        val extract = tinyButton("解压") { currentPreviewFile?.let { extractArchiveToCurrentDir(it) } }
        val minimize = tinyButton("最小") { showMinimizedBubble() }
        backButton = back
        saveButton = save
        openButton = open
        shareButton = share
        extractButton = extract
        minimizeButton = minimize

        toolbar.addView(back)
        toolbar.addView(save)
        toolbar.addView(open)
        toolbar.addView(share)
        toolbar.addView(extract)
        toolbar.addView(minimize)
        toolbar.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        return toolbar
    }

    private fun bindPanelScaffold() {
        val tab = activeTab()
        titleView?.text = if (previewing) {
            currentPreviewFile?.name ?: "预览"
        } else {
            "${tab.title} · ${tab.currentDir.absolutePath}"
        }

        backButton?.text = if (previewing) "返回" else "上级"
        saveButton?.visibility = if (previewing && currentPreviewFile?.let(::isTextFile) == true) View.VISIBLE else View.GONE
        openButton?.visibility = if (previewing) View.VISIBLE else View.GONE
        shareButton?.visibility = if (previewing) View.VISIBLE else View.GONE
        extractButton?.visibility = if (previewing && currentPreviewFile?.let { isArchiveFile(it) } == true) View.VISIBLE else View.GONE
        minimizeButton?.visibility = View.VISIBLE

        val browserVisibility = if (previewing) View.GONE else View.VISIBLE
        tabsScroll?.visibility = browserVisibility
        quickRootsScroll?.visibility = browserVisibility
        breadcrumbScroll?.visibility = browserVisibility
        controlBarScroll?.visibility = browserVisibility

        if (!previewing) {
            rebuildTabs()
            rebuildQuickRoots()
            rebuildBreadcrumb()
            rebuildControlBar()
            updateLayoutManager()
        }
    }

    private fun rebuildTabs() {
        val row = tabsRow ?: return
        val currentTabId = activeTab().id
        row.removeAllViews()
        tabs.forEach { tab ->
            row.addView(tabChip(tab, tab.id == currentTabId))
        }
        row.addView(chip("＋ 新页", false) {
            if (tabs.size >= MAX_TABS) {
                Toast.makeText(this, "最多同时打开 $MAX_TABS 个标签页", Toast.LENGTH_SHORT).show()
            } else {
                val next = createTab(activeTab().currentDir)
                activeTabId = next.id
                releasePlayer()
                previewing = false
                currentPreviewFile = null
                clearSelection()
                bindPanelScaffold()
                renderDirectoryState(forceReload = true)
            }
        })
    }

    private fun tabChip(tab: FileTab, selected: Boolean): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(8), dp(6))
            background = rounded(
                if (selected) 0xFF2F5F9F.toInt() else 0xFF202020.toInt(),
                16,
                1,
                if (selected) 0xFF6EA7FF.toInt() else 0xFF3A3A3A.toInt(),
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(0, 0, dp(6), 0)
            }
            setOnClickListener {
                if (activeTabId != tab.id) {
                    releasePlayer()
                    previewing = false
                    currentPreviewFile = null
                    clearSelection()
                    activeTabId = tab.id
                    bindPanelScaffold()
                    renderDirectoryState(forceReload = tab.entries.isEmpty())
                }
            }
            setOnLongClickListener {
                showTabMenu(this, tab)
                true
            }
        }
        box.addView(TextView(this).apply {
            text = if (tab.pinned) "[P] ${tab.title}" else tab.title
            setTextColor(Color.WHITE)
            textSize = 12f
            maxLines = 1
        })
        if (!tab.pinned && tabs.size > 1) {
            box.addView(TextView(this).apply {
                text = " ×"
                setTextColor(0xFFD6E7FF.toInt())
                textSize = 12f
                setOnClickListener { closeTab(tab.id) }
            })
        }
        return box
    }

    private fun showTabMenu(anchor: View, tab: FileTab) {
        PopupMenu(this, anchor).apply {
            menu.add(0, 1, 0, "复制标签")
            menu.add(0, 2, 1, if (tab.pinned) "取消固定" else "固定标签")
            menu.add(0, 3, 2, "跳到应用私有")
            menu.add(0, 4, 3, "跳到内部存储")
            if (!tab.pinned && tabs.size > 1) {
                menu.add(0, 5, 4, "关闭标签")
            }
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> {
                        if (tabs.size >= MAX_TABS) {
                            Toast.makeText(this@FloatingFileManagerService, "最多同时打开 $MAX_TABS 个标签页", Toast.LENGTH_SHORT).show()
                        } else {
                            val duplicated = createTab(tab.currentDir, pinned = false)
                            duplicated.entries = tab.entries
                            activeTabId = duplicated.id
                            bindPanelScaffold()
                            renderDirectoryState(forceReload = duplicated.entries.isEmpty())
                        }
                        true
                    }
                    2 -> {
                        tab.pinned = !tab.pinned
                        bindPanelScaffold()
                        true
                    }
                    3 -> {
                        activeTabId = tab.id
                        setActiveDir(appPrivateRoot())
                        renderDirectoryState(forceReload = true)
                        true
                    }
                    4 -> {
                        activeTabId = tab.id
                        setActiveDir(defaultSharedRoot())
                        renderDirectoryState(forceReload = true)
                        true
                    }
                    5 -> {
                        closeTab(tab.id)
                        true
                    }
                    else -> false
                }
            }
            show()
        }
    }

    private fun closeTab(id: Int) {
        if (tabs.size <= 1) {
            val tab = tabs.firstOrNull() ?: return
            tab.currentDir = defaultSharedRoot()
            tab.title = shortDirLabel(tab.currentDir)
            tab.entries = emptyList()
            activeTabId = tab.id
            rememberRecentDir(tab.currentDir)
            clearSelection()
            renderDirectoryState(forceReload = true)
            return
        }
        val index = tabs.indexOfFirst { it.id == id }
        if (index < 0) {
            return
        }
        val wasActive = activeTabId == id
        tabs.removeAt(index)
        if (wasActive) {
            releasePlayer()
            val nextIndex = min(index, tabs.lastIndex)
            activeTabId = tabs[nextIndex].id
            previewing = false
            currentPreviewFile = null
            clearSelection()
        }
        bindPanelScaffold()
        renderDirectoryState(forceReload = activeTab().entries.isEmpty())
    }

    private fun rebuildQuickRoots() {
        val row = quickRootsRow ?: return
        val currentDir = activeTab().currentDir
        row.removeAllViews()
        quickRootFiles().forEach { (label, file) ->
            if (file.exists()) {
                row.addView(chip(label, currentDir.absolutePath == file.absolutePath) {
                    setActiveDir(file)
                    renderDirectoryState(forceReload = true)
                })
            }
        }
    }

    private fun rebuildBreadcrumb() {
        val row = breadcrumbRow ?: return
        val currentDir = activeTab().currentDir
        val (baseLabel, baseDir) = breadcrumbBase(currentDir)
        row.removeAllViews()
        row.addView(chip(baseLabel, currentDir.absolutePath == baseDir.absolutePath) {
            setActiveDir(baseDir)
            renderDirectoryState(forceReload = true)
        })
        val segments = breadcrumbSegments(baseDir, currentDir)
        var cursor = baseDir
        segments.forEach { part ->
            row.addView(TextView(this).apply {
                text = "›"
                setTextColor(0xFF777777.toInt())
                textSize = 16f
                setPadding(dp(4), 0, dp(4), 0)
            })
            cursor = if (cursor.absolutePath == File.separator) {
                File(File.separator, part)
            } else {
                File(cursor, part)
            }
            val target = cursor
            row.addView(chip(part, currentDir.absolutePath == target.absolutePath) {
                setActiveDir(target)
                renderDirectoryState(forceReload = true)
            })
        }
    }

    private fun breadcrumbBase(dir: File): Pair<String, File> {
        val privateRoot = appPrivateRoot()
        val sharedRoot = defaultSharedRoot()
        return when {
            dir.absolutePath.startsWith(privateRoot.absolutePath) -> "应用私有" to privateRoot
            dir.absolutePath.startsWith(sharedRoot.absolutePath) -> "内部存储" to sharedRoot
            else -> "/" to File(File.separator)
        }
    }

    private fun breadcrumbSegments(baseDir: File, currentDir: File): List<String> {
        return if (baseDir.absolutePath == File.separator) {
            currentDir.absolutePath.trim(File.separatorChar)
                .split(File.separatorChar)
                .filter { it.isNotBlank() }
        } else {
            currentDir.relativeToOrNull(baseDir)?.path
                ?.split(File.separatorChar)
                ?.filter { it.isNotBlank() && it != "." }
                ?: emptyList()
        }
    }

    private fun rebuildControlBar() {
        val row = controlBarRow ?: return
        row.removeAllViews()
        if (selectionMode) {
            row.addView(chip("已选 ${selectedPaths.size}", true) {})
            row.addView(chip("全选", false) { selectAllVisible() })
            if (selectedPaths.size == 1) {
                row.addView(chip("重命名", false) { renameSelected() })
            }
            row.addView(chip("压缩", false) { compressFilesPrompt(selectedFiles()) })
            row.addView(chip("复制", false) { captureClipboard(move = false) })
            row.addView(chip("移动", false) { captureClipboard(move = true) })
            row.addView(chip("删除", false) { deleteSelected() })
            row.addView(chip("取消", false) { clearSelection() })
            return
        }

        clipboard?.let {
            row.addView(chip(if (it.move) "粘贴移动" else "粘贴复制", true) {
                pasteClipboard()
            })
        }
        val currentDir = activeTab().currentDir
        row.addView(
            chip(
                if (isFavoriteDir(currentDir)) "取消收藏" else "收藏当前",
                isFavoriteDir(currentDir),
            ) {
                toggleFavoriteDir(currentDir)
            },
        )
        val favoritesChip = chip("收藏夹", favoriteDirs.isNotEmpty()) {}
        favoritesChip.setOnClickListener {
            showDirectoryCollectionMenu(
                anchor = favoritesChip,
                title = "收藏夹为空",
                directories = favoriteDirectoryFiles(),
            )
        }
        row.addView(favoritesChip)
        val recentChip = chip("最近", recentDirs.isNotEmpty()) {}
        recentChip.setOnClickListener {
            showDirectoryCollectionMenu(
                anchor = recentChip,
                title = "最近目录为空",
                directories = recentDirectoryFiles(),
                allowClear = true,
            )
        }
        row.addView(recentChip)
        row.addView(chip("新建", false) { createFolderPrompt() })
        row.addView(chip("多选", false) {
            selectionMode = true
            bindPanelScaffold()
            fileAdapter?.notifyDataSetChanged()
        })
        row.addView(chip(if (viewMode == ViewMode.LIST) "列表" else "网格", true) {
            viewMode = if (viewMode == ViewMode.LIST) ViewMode.GRID else ViewMode.LIST
            fileAdapter?.setViewMode(viewMode)
            updateLayoutManager()
        })
        row.addView(chip(sortMode.label, false) {
            sortMode = sortMode.next()
            renderDirectoryState(forceReload = true)
        })
        row.addView(chip(if (showHidden) "隐藏:开" else "隐藏:关", showHidden) {
            showHidden = !showHidden
            renderDirectoryState(forceReload = true)
        })
        row.addView(chip("刷新", false) { renderDirectoryState(forceReload = true) })
    }

    private fun updateLayoutManager() {
        val recycler = recyclerView ?: return
        recycler.layoutManager = when (viewMode) {
            ViewMode.LIST -> LinearLayoutManager(this)
            ViewMode.GRID -> GridLayoutManager(this, gridSpanCount())
        }
    }

    private fun clearSelection() {
        selectionMode = false
        selectedPaths.clear()
        bindPanelScaffold()
        fileAdapter?.notifyDataSetChanged()
    }

    private fun selectAllVisible() {
        val files = activeTab().entries
            .filter { !it.isParent && it.file != null }
            .map { it.file!!.absolutePath }
        selectedPaths.clear()
        selectedPaths.addAll(files)
        selectionMode = selectedPaths.isNotEmpty()
        bindPanelScaffold()
        fileAdapter?.notifyDataSetChanged()
    }

    private fun renderDirectoryState(forceReload: Boolean) {
        previewing = false
        currentPreviewFile = null
        currentTextEditor = null
        updateOverlayFocusability(false)
        bindPanelScaffold()
        val tab = activeTab()
        if (forceReload) {
            loadDirectoryAsync(tab.id, tab.currentDir)
        } else {
            fileAdapter?.submitList(tab.entries)
            showContent(if (tab.entries.isEmpty()) "没有文件，或当前目录无读取权限" else null)
            updateDirectoryStatus(tab)
        }
    }

    private fun loadDirectoryAsync(tabId: Int, requestedDir: File) {
        val tab = findTab(tabId) ?: return
        val requestId = requestIdGenerator.incrementAndGet()
        tab.lastRequestId = requestId
        tab.currentDir = requestedDir
        tab.title = shortDirLabel(requestedDir)
        showContent("正在读取目录...")
        statusView?.text = requestedDir.absolutePath

        worker.execute {
            val files = visibleFiles(requestedDir)
            val entries = buildEntries(requestedDir, files)
            mainHandler.post {
                val targetTab = findTab(tabId) ?: return@post
                if (targetTab.lastRequestId != requestId || targetTab.currentDir.absolutePath != requestedDir.absolutePath) {
                    return@post
                }
                targetTab.entries = entries
                targetTab.title = shortDirLabel(targetTab.currentDir)
                if (!previewing && activeTabId == tabId) {
                    bindPanelScaffold()
                    fileAdapter?.submitList(entries)
                    showContent(if (entries.isEmpty()) "没有文件，或当前目录无读取权限" else null)
                    updateDirectoryStatus(targetTab)
                }
            }
        }
    }

    private fun buildEntries(dir: File, files: List<File>): List<FileEntry> {
        val entries = mutableListOf<FileEntry>()
        dir.parentFile?.let { parent ->
            entries.add(
                FileEntry(
                    title = "..",
                    meta = "返回上级目录",
                    file = parent,
                    isDirectory = true,
                    isParent = true,
                ),
            )
        }
        files.forEach { file ->
            entries.add(
                FileEntry(
                    title = file.name,
                    meta = fileMeta(file),
                    file = file,
                    isDirectory = file.isDirectory,
                    isParent = false,
                ),
            )
        }
        return entries
    }

    private fun showContent(message: String?) {
        val container = contentContainer ?: return
        container.removeAllViews()
        if (message != null) {
            loadingView?.text = message
            loadingView?.let {
                container.addView(
                    it,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            }
        } else {
            recyclerView?.let {
                container.addView(
                    it,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            }
        }
    }

    private fun updateDirectoryStatus(tab: FileTab) {
        val folderCount = tab.entries.count { !it.isParent && it.isDirectory }
        val fileCount = tab.entries.count { !it.isParent && !it.isDirectory }
        val activeIndex = tabs.indexOfFirst { it.id == tab.id } + 1
        val clipboardText = clipboard?.let {
            val label = if (it.move) "移动剪贴板" else "复制剪贴板"
            " · $label ${it.files.size} 项"
        } ?: ""
        statusView?.text = "标签 $activeIndex/${tabs.size} · $folderCount 个文件夹 · $fileCount 个文件$clipboardText\n${tab.currentDir.absolutePath}"
    }

    private fun openPreview(file: File) {
        releasePlayer()
        currentTextEditor = null
        previewing = true
        currentPreviewFile = file
        bindPanelScaffold()
        statusView?.text = "${formatSize(file.length())} · ${formatDate(file.lastModified())} · ${file.absolutePath}"

        val ext = file.extension.lowercase(Locale.ROOT)
        val previewView = when {
            ext in textExtensions -> textPreview(file)
            ext in imageExtensions -> imagePreview(file)
            ext in videoExtensions -> mediaPreview(file, isVideo = true)
            ext in audioExtensions -> audioPreview(file)
            ext in archiveExtensions -> archivePreview(file)
            else -> unsupportedPreview()
        }

        contentContainer?.removeAllViews()
        contentContainer?.addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        updateOverlayFocusability(isTextFile(file), currentTextEditor)
    }

    private fun closePreview() {
        releasePlayer()
        currentTextEditor = null
        previewing = false
        currentPreviewFile = null
        updateOverlayFocusability(false)
        bindPanelScaffold()
        renderDirectoryState(forceReload = false)
    }

    private fun textPreview(file: File): View {
        val text = try {
            file.inputStream().bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            "读取失败: ${e.message}"
        }
        return ScrollView(this).apply {
            addView(CodeEditorEditText(context).apply {
                currentTextEditor = this
                setText(text)
                setSelection(text.length.coerceAtMost(length()))
            })
        }
    }

    private fun saveCurrentTextFile() {
        val file = currentPreviewFile ?: return
        val editor = currentTextEditor ?: return
        val content = editor.text?.toString().orEmpty()
        showOperationProgress("正在保存", 0, 1, file.name)
        worker.execute {
            try {
                file.writeText(content)
                mainHandler.post {
                    showOperationProgress("保存完成", 1, 1, file.name)
                    statusView?.text = "${formatSize(file.length())} · ${formatDate(file.lastModified())} · ${file.absolutePath}"
                    mainHandler.postDelayed({ hideOperationProgress() }, 700)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    hideOperationProgress()
                    Toast.makeText(this, "保存失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun restoreDirectoryCollections() {
        favoriteDirs.clear()
        favoriteDirs.addAll(readStoredPaths(KEY_FAVORITES))
        recentDirs.clear()
        recentDirs.addAll(readStoredPaths(KEY_RECENTS))
        cleanupDirectoryCollections(persist = false)
    }

    private fun readStoredPaths(key: String): List<String> {
        return prefs.getString(key, "").orEmpty()
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }

    private fun persistDirectoryCollections() {
        prefs.edit()
            .putString(KEY_FAVORITES, favoriteDirs.joinToString("\n"))
            .putString(KEY_RECENTS, recentDirs.joinToString("\n"))
            .apply()
    }

    private fun cleanupDirectoryCollections(persist: Boolean = true) {
        val validFavorites = favoriteDirs.filter { File(it).isDirectory }
        val validRecents = recentDirs
            .filter { File(it).isDirectory }
            .distinct()
            .take(MAX_RECENT_DIRS)
        val changed = validFavorites.size != favoriteDirs.size || validRecents != recentDirs
        if (changed) {
            favoriteDirs.clear()
            favoriteDirs.addAll(validFavorites)
            recentDirs.clear()
            recentDirs.addAll(validRecents)
            if (persist) {
                persistDirectoryCollections()
            }
        }
    }

    private fun rememberRecentDir(dir: File) {
        if (!dir.isDirectory) {
            return
        }
        val path = dir.absolutePath
        recentDirs.remove(path)
        recentDirs.add(0, path)
        while (recentDirs.size > MAX_RECENT_DIRS) {
            recentDirs.removeAt(recentDirs.lastIndex)
        }
        persistDirectoryCollections()
    }

    private fun isFavoriteDir(dir: File): Boolean = favoriteDirs.contains(dir.absolutePath)

    private fun toggleFavoriteDir(dir: File) {
        val path = dir.absolutePath
        val added = if (favoriteDirs.contains(path)) {
            favoriteDirs.remove(path)
            false
        } else {
            favoriteDirs.add(path)
            true
        }
        persistDirectoryCollections()
        bindPanelScaffold()
        Toast.makeText(this, if (added) "已收藏当前目录" else "已取消收藏", Toast.LENGTH_SHORT).show()
    }

    private fun favoriteDirectoryFiles(): List<File> {
        cleanupDirectoryCollections()
        return favoriteDirs.map(::File).filter { it.isDirectory }
    }

    private fun recentDirectoryFiles(): List<File> {
        cleanupDirectoryCollections()
        return recentDirs.map(::File).filter { it.isDirectory }
    }

    private fun showDirectoryCollectionMenu(
        anchor: View,
        title: String,
        directories: List<File>,
        allowClear: Boolean = false,
    ) {
        if (directories.isEmpty()) {
            Toast.makeText(this, title, Toast.LENGTH_SHORT).show()
            return
        }
        PopupMenu(this, anchor).apply {
            directories.forEachIndexed { index, dir ->
                val label = "${shortDirLabel(dir)} · ${dir.absolutePath}"
                menu.add(0, 1000 + index, index, label)
            }
            if (allowClear) {
                menu.add(0, 5000, directories.size + 1, "清空最近")
            }
            setOnMenuItemClickListener { item ->
                when {
                    item.itemId == 5000 -> {
                        recentDirs.clear()
                        persistDirectoryCollections()
                        bindPanelScaffold()
                        true
                    }
                    item.itemId >= 1000 -> {
                        val index = item.itemId - 1000
                        directories.getOrNull(index)?.let { dir ->
                            setActiveDir(dir)
                            renderDirectoryState(forceReload = true)
                        }
                        true
                    }
                    else -> false
                }
            }
            show()
        }
    }

    private fun imagePreview(file: File): View {
        return FrameLayout(this).apply {
            addView(
                android.widget.ImageView(context).apply {
                    scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
                    adjustViewBounds = true
                    setImageURI(Uri.fromFile(file))
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
        }
    }

    private fun archivePreview(file: File): View {
        val text = try {
            ZipFile(file).use { zip ->
                val lines = mutableListOf<String>()
                val entries: Enumeration<out ZipEntry> = zip.entries()
                var count = 0
                while (entries.hasMoreElements() && count < 300) {
                    val entry = entries.nextElement()
                    val suffix = if (entry.isDirectory) "/" else " (${formatSize(entry.size)})"
                    lines.add(entry.name + suffix)
                    count++
                }
                val more = if (zip.size() > count) "\n...\n共 ${zip.size()} 项" else "\n\n共 ${zip.size()} 项"
                (lines.joinToString("\n") + more).ifBlank { "压缩包为空" }
            }
        } catch (e: Exception) {
            "读取压缩包失败: ${e.message}"
        }
        return ScrollView(this).apply {
            addView(TextView(context).apply {
                this.text = text
                setTextColor(Color.WHITE)
                textSize = 12f
                typeface = Typeface.MONOSPACE
                setPadding(dp(12), dp(12), dp(12), dp(12))
            })
        }
    }

    private fun audioPreview(file: File): View {
        val player = ExoPlayer.Builder(this).build()
        currentPlayer = player
        val info = try {
            MediaToolbox.readMediaInfo(file)
        } catch (_: Exception) {
            null
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            setBackgroundColor(Color.BLACK)
        }

        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(0xFF11161E.toInt(), 18, 1, 0xFF263445.toInt())
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        val coverFrame = FrameLayout(this).apply {
            background = rounded(0xFF1B2430.toInt(), 16, 1, 0xFF314357.toInt())
        }
        val coverSize = dp(92)
        if (info?.embeddedArt != null) {
            val bitmap = BitmapFactory.decodeByteArray(info.embeddedArt, 0, info.embeddedArt.size)
            coverFrame.addView(
                ImageView(this).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    setImageBitmap(bitmap)
                },
                FrameLayout.LayoutParams(coverSize, coverSize, Gravity.CENTER),
            )
        } else {
            coverFrame.addView(
                TextView(this).apply {
                    text = "AUDIO"
                    gravity = Gravity.CENTER
                    setTextColor(0xFFD7E6FF.toInt())
                    textSize = 16f
                    typeface = Typeface.DEFAULT_BOLD
                },
                FrameLayout.LayoutParams(coverSize, coverSize, Gravity.CENTER),
            )
        }
        hero.addView(
            coverFrame,
            LinearLayout.LayoutParams(coverSize, coverSize),
        )

        val infoColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        infoColumn.addView(TextView(this).apply {
            text = info?.title?.takeIf { it.isNotBlank() } ?: file.nameWithoutExtension.ifBlank { file.name }
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 2
        })
        infoColumn.addView(TextView(this).apply {
            text = buildString {
                append(info?.artist?.takeIf { it.isNotBlank() } ?: "未知艺术家")
                val album = info?.album?.takeIf { it.isNotBlank() }
                if (album != null) {
                    append(" · ")
                    append(album)
                }
            }
            setTextColor(0xFF9FB0C5.toInt())
            textSize = 12f
            maxLines = 2
        })
        infoColumn.addView(TextView(this).apply {
            text = buildString {
                val duration = info?.durationMs?.takeIf { it > 0 }?.let(MediaToolbox::formatDuration) ?: "--:--"
                append(duration)
                info?.bitrate?.takeIf { it > 0 }?.let {
                    append(" · ")
                    append("${it / 1000} kbps")
                }
                info?.sampleRate?.takeIf { it > 0 }?.let {
                    append(" · ")
                    append("${it} Hz")
                }
            }
            setTextColor(0xFF7F8DA3.toInt())
            textSize = 11f
            maxLines = 2
            setPadding(0, dp(8), 0, 0)
        })
        hero.addView(
            infoColumn,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        container.addView(hero)

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, dp(8))
        }
        actionRow.addView(chip("媒体信息", false) { showMediaInfoDialog(file) })
        if (file.extension.lowercase(Locale.ROOT) != "mp3") {
            actionRow.addView(chip("转 MP3", false) { convertAudioToMp3Prompt(file) })
        }
        container.addView(actionRow)

        val controlView = PlayerControlView(this).apply {
            setPlayer(player)
            setShowTimeoutMs(0)
            setShowNextButton(false)
            setShowPreviousButton(false)
            setShowShuffleButton(false)
            setBackgroundColor(0xFF101010.toInt())
        }
        container.addView(
            controlView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(4)
            },
        )

        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Toast.makeText(
                    this@FloatingFileManagerService,
                    "音频播放失败，请尝试外部应用打开",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        })
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
        player.prepare()
        player.playWhenReady = true
        return ScrollView(this).apply { addView(container) }
    }

    private fun mediaPreview(file: File, isVideo: Boolean): View {
        val player = ExoPlayer.Builder(this).build()
        currentPlayer = player

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
        }

        val mediaSurface = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        container.addView(
            mediaSurface,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        var textureView: TextureView? = null
        if (isVideo) {
            val videoTextureView = TextureView(this)
            textureView = videoTextureView
            mediaSurface.addView(
                videoTextureView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
            player.setVideoTextureView(videoTextureView)
        } else {
            mediaSurface.addView(
                TextView(this).apply {
                    text = "音频预览"
                    setTextColor(Color.WHITE)
                    textSize = 18f
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
        }

        val controlView = PlayerControlView(this).apply {
            setPlayer(currentPlayer)
            setShowTimeoutMs(0)
            setShowNextButton(false)
            setShowPreviousButton(false)
            setShowShuffleButton(false)
        }
        container.addView(
            controlView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        if (isVideo) {
            container.addView(
                LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(dp(12), dp(10), dp(12), dp(12))
                    addView(chip("媒体信息", false) { showMediaInfoDialog(file) })
                    addView(chip("提取音频", false) { extractAudioFromVideoPrompt(file) })
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

        fun updateVideoBounds(videoSize: VideoSize) {
            val targetView = textureView ?: return
            mediaSurface.post {
                val containerWidth = mediaSurface.width
                val containerHeight = mediaSurface.height
                if (containerWidth <= 0 || containerHeight <= 0 || videoSize.height <= 0) {
                    return@post
                }
                val pixelRatio =
                    if (videoSize.pixelWidthHeightRatio > 0f) videoSize.pixelWidthHeightRatio else 1f
                val videoRatio = (videoSize.width * pixelRatio) / videoSize.height.toFloat()
                var targetWidth = containerWidth
                var targetHeight = (targetWidth / videoRatio).roundToInt()
                if (targetHeight > containerHeight) {
                    targetHeight = containerHeight
                    targetWidth = (targetHeight * videoRatio).roundToInt()
                }
                val layoutParams = targetView.layoutParams as FrameLayout.LayoutParams
                if (layoutParams.width != targetWidth || layoutParams.height != targetHeight) {
                    layoutParams.width = targetWidth
                    layoutParams.height = targetHeight
                    layoutParams.gravity = Gravity.CENTER
                    targetView.layoutParams = layoutParams
                }
            }
        }

        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Toast.makeText(
                    this@FloatingFileManagerService,
                    "悬浮窗无法播放此文件，请用外部应用打开",
                    Toast.LENGTH_SHORT,
                ).show()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                updateVideoBounds(videoSize)
            }
        })
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
        player.prepare()
        player.playWhenReady = true
        if (isVideo) {
            mediaSurface.post {
                player.videoSize.takeIf { it != VideoSize.UNKNOWN }?.let(::updateVideoBounds)
            }
        }
        return container
    }

    private fun unsupportedPreview(): View {
        return FrameLayout(this).apply {
            addView(
                TextView(context).apply {
                    text = "此格式不支持悬浮预览，可点击“打开”调用外部应用。"
                    setTextColor(0xFFB8B8B8.toInt())
                    gravity = Gravity.CENTER
                    textSize = 13f
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
        }
    }

    private fun releasePlayer() {
        currentPlayer?.release()
        currentPlayer = null
    }

    private fun openExternal(file: File) {
        try {
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeFor(file))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "打开文件").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (_: Exception) {
            Toast.makeText(this, "没有可打开此文件的应用", Toast.LENGTH_SHORT).show()
        }
    }

    private fun shareFile(file: File) {
        try {
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeFor(file)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "分享文件").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (_: Exception) {
            Toast.makeText(this, "无法分享此文件", Toast.LENGTH_SHORT).show()
        }
    }

    private fun goParent() {
        if (previewing) {
            closePreview()
            return
        }
        val currentDir = activeTab().currentDir
        val parent = currentDir.parentFile
        if (parent != null && parent.canRead()) {
            setActiveDir(parent)
            renderDirectoryState(forceReload = true)
        } else {
            showMinimizedBubble()
        }
    }

    private fun createFolderPrompt() {
        val currentDir = activeTab().currentDir
        showTextInputDialog("新建文件夹", "输入文件夹名", "New Folder") { name ->
            val target = File(currentDir, name)
            if (target.exists()) {
                Toast.makeText(this, "目标已存在", Toast.LENGTH_SHORT).show()
                return@showTextInputDialog
            }
            if (target.mkdirs()) {
                renderDirectoryState(forceReload = true)
            } else {
                Toast.makeText(this, "创建失败", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun renameSelected() {
        val file = selectedFiles().singleOrNull() ?: return
        renameFile(file)
    }

    private fun renameFile(file: File) {
        showTextInputDialog("重命名", "输入新名称", file.name) { input ->
            val parent = file.parentFile ?: return@showTextInputDialog
            val target = File(parent, input)
            if (target.exists() && target.absolutePath != file.absolutePath) {
                Toast.makeText(this, "目标已存在", Toast.LENGTH_SHORT).show()
                return@showTextInputDialog
            }
            if (file.renameTo(target)) {
                clearSelection()
                renderDirectoryState(forceReload = true)
            } else {
                Toast.makeText(this, "重命名失败", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun captureClipboard(move: Boolean, files: List<File> = selectedFiles()) {
        if (files.isEmpty()) {
            Toast.makeText(this, "没有可操作的文件", Toast.LENGTH_SHORT).show()
            return
        }
        clipboard = ClipboardState(files = files.map { it.absoluteFile }, move = move)
        clearSelection()
        renderDirectoryState(forceReload = false)
        Toast.makeText(this, if (move) "已加入移动剪贴板" else "已加入复制剪贴板", Toast.LENGTH_SHORT).show()
    }

    private fun pasteClipboard() {
        val clip = clipboard ?: return
        val targetDir = activeTab().currentDir
        showLoading("正在粘贴...")
        worker.execute {
            try {
                val existingFiles = clip.files.filter { it.exists() }
                val total = existingFiles.sumOf { countPathUnits(it) }.coerceAtLeast(1)
                val progress = createProgressUpdater(
                    title = if (clip.move) "正在移动" else "正在复制",
                    total = total,
                )
                clip.files.forEach { source ->
                    if (!source.exists()) {
                        return@forEach
                    }
                    val destination = uniqueDestination(targetDir, source.name)
                    if (clip.move) {
                        movePath(source, destination, progress)
                    } else {
                        copyPath(source, destination, progress)
                    }
                }
                mainHandler.post {
                    if (clip.move) {
                        clipboard = null
                    }
                    hideOperationProgress()
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "粘贴完成", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                mainHandler.post {
                    hideOperationProgress()
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "粘贴失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun deleteSelected() {
        val files = selectedFiles()
        if (files.isEmpty()) {
            return
        }
        showConfirmDialog("删除 ${files.size} 项？") {
            showLoading("正在删除...")
            worker.execute {
                try {
                    val total = files.sumOf { countPathUnits(it) }.coerceAtLeast(1)
                    val progress = createProgressUpdater("正在删除", total)
                    files.forEach { deletePath(it, progress) }
                    mainHandler.post {
                        hideOperationProgress()
                        clearSelection()
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, "删除完成", Toast.LENGTH_SHORT).show()
                    }
                } catch (e: Exception) {
                    mainHandler.post {
                        hideOperationProgress()
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, "删除失败: ${e.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    private fun extractArchiveToCurrentDir(archive: File) {
        if (!isArchiveFile(archive)) {
            Toast.makeText(this, "当前文件不是可解压压缩包", Toast.LENGTH_SHORT).show()
            return
        }
        val targetRoot = uniqueDestination(activeTab().currentDir, archive.nameWithoutExtension.ifBlank { "archive" })
        showLoading("正在解压...")
        worker.execute {
            try {
                val total = countArchiveEntries(archive).coerceAtLeast(1)
                val progress = createProgressUpdater("正在解压", total)
                unzipToDirectory(archive, targetRoot, progress)
                mainHandler.post {
                    hideOperationProgress()
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "已解压到 ${targetRoot.name}", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                mainHandler.post {
                    hideOperationProgress()
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "解压失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun compressFilesPrompt(files: List<File>) {
        if (files.isEmpty()) {
            Toast.makeText(this, "没有可压缩的文件", Toast.LENGTH_SHORT).show()
            return
        }
        val suggestionBase = when {
            files.size == 1 -> files.first().nameWithoutExtension.ifBlank { files.first().name }
            else -> "${activeTab().currentDir.name.ifBlank { "archive" }}-${SimpleDateFormat("MMdd-HHmm", Locale.ROOT).format(Date())}"
        }
        val defaultName = ensureZipFileName(suggestionBase)
        showTextInputDialog("压缩为 ZIP", "输入压缩包名称", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, ensureZipFileName(input))
            showLoading("正在压缩...")
            worker.execute {
                try {
                    val total = files.sumOf { countPathUnits(it) }.coerceAtLeast(1)
                    val progress = createProgressUpdater("正在压缩", total)
                    zipPaths(target, files, progress)
                    mainHandler.post {
                        hideOperationProgress()
                        clearSelection()
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, "已生成 ${target.name}", Toast.LENGTH_SHORT).show()
                    }
                } catch (e: Exception) {
                    mainHandler.post {
                        hideOperationProgress()
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, "压缩失败: ${e.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    private fun selectedFiles(): List<File> {
        return selectedPaths.map(::File).filter { it.exists() }
    }

    private fun showLoading(message: String) {
        if (!previewing) {
            showContent(message)
        }
        showOperationProgress(message, detail = activeTab().currentDir.absolutePath, indeterminate = true)
    }

    private fun showOperationProgress(
        title: String,
        current: Int? = null,
        total: Int? = null,
        detail: String? = null,
        indeterminate: Boolean = current == null || total == null || total <= 0,
    ) {
        operationContainer?.visibility = View.VISIBLE
        operationProgressBar?.isIndeterminate = indeterminate
        if (!indeterminate) {
            val safeTotal = max(1, total ?: 1)
            val safeCurrent = min(current ?: 0, safeTotal)
            operationProgressBar?.progress = (safeCurrent * 1000) / safeTotal
            operationView?.text = buildString {
                append("$title · $safeCurrent/$safeTotal")
                if (!detail.isNullOrBlank()) {
                    append('\n')
                    append(detail)
                }
            }
        } else {
            operationProgressBar?.progress = 0
            operationView?.text = if (detail.isNullOrBlank()) title else "$title\n$detail"
        }
    }

    private fun hideOperationProgress() {
        operationContainer?.visibility = View.GONE
        operationProgressBar?.isIndeterminate = false
        operationProgressBar?.progress = 0
        operationView?.text = ""
    }

    private fun createProgressUpdater(title: String, total: Int): (Int, String) -> Unit {
        val safeTotal = max(1, total)
        var completed = 0
        return { delta, detail ->
            completed = min(safeTotal, completed + max(1, delta))
            mainHandler.post {
                showOperationProgress(title, completed, safeTotal, detail)
            }
        }
    }

    private fun showTextInputDialog(title: String, hint: String, initialValue: String, onConfirm: (String) -> Unit) {
        val input = EditText(this).apply {
            setText(initialValue)
            setSelection(initialValue.length)
            this.hint = hint
            inputType = InputType.TYPE_CLASS_TEXT
            setTextColor(Color.WHITE)
            setHintTextColor(0xFF888888.toInt())
            setBackgroundColor(0xFF1E1E1E.toInt())
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setView(input)
            .setPositiveButton("确定") { _, _ ->
                val value = input.text?.toString()?.trim().orEmpty()
                if (value.isNotEmpty()) {
                    onConfirm(value)
                }
            }
            .setNegativeButton("取消", null)
            .create()
        dialog.window?.setType(overlayType())
        dialog.show()
        input.post {
            input.requestFocus()
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun showConfirmDialog(message: String, onConfirm: () -> Unit) {
        val dialog = AlertDialog.Builder(this)
            .setMessage(message)
            .setPositiveButton("确定") { _, _ -> onConfirm() }
            .setNegativeButton("取消", null)
            .create()
        dialog.window?.setType(overlayType())
        dialog.show()
    }

    private fun showMediaInfoDialog(file: File) {
        val infoText = try {
            MediaToolbox.readMediaInfo(file).summaryLines(file).joinToString("\n")
        } catch (e: Exception) {
            "无法读取媒体信息: ${e.message}"
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle("媒体信息")
            .setMessage(infoText)
            .setPositiveButton("确定", null)
            .create()
        dialog.window?.setType(overlayType())
        dialog.show()
    }

    private fun convertAudioToMp3Prompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}.mp3"
        showTextInputDialog("转为 MP3", "输出文件名", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, if (input.endsWith(".mp3", true)) input else "$input.mp3")
            showLoading("FFmpeg 正在转码音频...")
            worker.execute {
                val result = MediaToolbox.convertAudioToMp3(file, target)
                mainHandler.post {
                    hideOperationProgress()
                    if (result.success) {
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, result.message, Toast.LENGTH_SHORT).show()
                    } else {
                        Toast.makeText(this, result.message, Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    private fun extractAudioFromVideoPrompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}.m4a"
        showTextInputDialog("提取音频", "输出文件名", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, if (input.endsWith(".m4a", true)) input else "$input.m4a")
            showLoading("FFmpeg 正在提取音频...")
            worker.execute {
                val result = MediaToolbox.extractAudioFromVideo(file, target)
                mainHandler.post {
                    hideOperationProgress()
                    if (result.success) {
                        renderDirectoryState(forceReload = true)
                        Toast.makeText(this, result.message, Toast.LENGTH_SHORT).show()
                    } else {
                        Toast.makeText(this, result.message, Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    private fun showItemMenu(anchor: View, entry: FileEntry) {
        val file = entry.file ?: return
        PopupMenu(this, anchor).apply {
            if (entry.isDirectory) {
                menu.add(0, 1, 0, "新标签打开")
            } else {
                menu.add(0, 2, 1, "预览")
            }
            menu.add(0, 3, 2, "重命名")
            menu.add(0, 4, 3, "复制")
            menu.add(0, 5, 4, "移动")
            menu.add(0, 6, 5, "删除")
            menu.add(0, 7, 6, "多选")
            menu.add(0, 9, 7, "压缩为 ZIP")
            if (!entry.isDirectory && isArchiveFile(file)) {
                menu.add(0, 8, 8, "解压到当前目录")
            }
            if (!entry.isDirectory && isAudioFile(file)) {
                menu.add(0, 10, 9, "转为 MP3")
                menu.add(0, 12, 10, "媒体信息")
            } else if (!entry.isDirectory && isVideoFile(file)) {
                menu.add(0, 11, 9, "提取音频")
                menu.add(0, 12, 10, "媒体信息")
            }
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> {
                        if (tabs.size >= MAX_TABS) {
                            Toast.makeText(this@FloatingFileManagerService, "最多同时打开 $MAX_TABS 个标签页", Toast.LENGTH_SHORT).show()
                        } else {
                            val next = createTab(file)
                            activeTabId = next.id
                            clearSelection()
                            bindPanelScaffold()
                            renderDirectoryState(forceReload = true)
                        }
                        true
                    }
                    2 -> {
                        openPreview(file)
                        true
                    }
                    3 -> {
                        renameFile(file)
                        true
                    }
                    4 -> {
                        captureClipboard(move = false, files = listOf(file))
                        true
                    }
                    5 -> {
                        captureClipboard(move = true, files = listOf(file))
                        true
                    }
                    6 -> {
                        selectedPaths.clear()
                        selectedPaths.add(file.absolutePath)
                        selectionMode = true
                        deleteSelected()
                        true
                    }
                    7 -> {
                        selectionMode = true
                        selectedPaths.add(file.absolutePath)
                        bindPanelScaffold()
                        fileAdapter?.notifyDataSetChanged()
                        true
                    }
                    8 -> {
                        extractArchiveToCurrentDir(file)
                        true
                    }
                    9 -> {
                        compressFilesPrompt(listOf(file))
                        true
                    }
                    10 -> {
                        convertAudioToMp3Prompt(file)
                        true
                    }
                    11 -> {
                        extractAudioFromVideoPrompt(file)
                        true
                    }
                    12 -> {
                        showMediaInfoDialog(file)
                        true
                    }
                    else -> false
                }
            }
            show()
        }
    }

    private fun attachDrag(view: View) {
        var startX = 0
        var startY = 0
        var downX = 0f
        var downY = 0f
        view.setOnTouchListener { _, event ->
            val lp = params ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    downX = event.rawX
                    downY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = startX + (event.rawX - downX).toInt()
                    lp.y = startY + (event.rawY - downY).toInt()
                    rootView?.let { windowManager.updateViewLayout(it, lp) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downX) + abs(event.rawY - downY)
                    if (moved < 12f) {
                        view.performClick()
                    }
                    true
                }
                else -> true
            }
        }
    }

    private fun visibleFiles(dir: File): List<File> {
        val files = dir.listFiles()
            ?.filter { showHidden || !it.isHidden }
            ?: emptyList()
        val comparator = when (sortMode) {
            SortMode.NAME -> compareBy<File>({ if (it.isDirectory) 0 else 1 }, { it.name.lowercase(Locale.ROOT) })
            SortMode.DATE -> compareBy<File>({ if (it.isDirectory) 0 else 1 }, { -it.lastModified() }, { it.name.lowercase(Locale.ROOT) })
            SortMode.SIZE -> compareBy<File>({ if (it.isDirectory) 0 else 1 }, { if (it.isDirectory) Long.MIN_VALUE else -it.length() }, { it.name.lowercase(Locale.ROOT) })
            SortMode.TYPE -> compareBy<File>({ if (it.isDirectory) 0 else 1 }, { fileTypeKey(it) }, { it.name.lowercase(Locale.ROOT) })
        }
        return files.sortedWith(comparator)
    }

    private fun fileTypeKey(file: File): String {
        return when {
            file.isDirectory -> "0-folder"
            isArchiveFile(file) -> "1-archive"
            file.extension.lowercase(Locale.ROOT).isBlank() -> "9-file"
            else -> file.extension.lowercase(Locale.ROOT)
        }
    }

    private fun fileMeta(file: File): String {
        return if (file.isDirectory) {
            "文件夹 · ${formatDate(file.lastModified())}"
        } else {
            "${formatSize(file.length())} · ${formatDate(file.lastModified())}"
        }
    }

    private fun quickRootFiles(): List<Pair<String, File>> {
        val sharedRoot = defaultSharedRoot()
        val privateRoot = appPrivateRoot()
        val externalPrivate = getExternalFilesDir(null)
        return buildList {
            add("内部" to sharedRoot)
            add("私有根" to privateRoot)
            add("files" to filesDir)
            add("cache" to cacheDir)
            if (noBackupFilesDir.exists()) {
                add("no_backup" to noBackupFilesDir)
            }
            if (externalPrivate != null && externalPrivate.exists()) {
                add("外部私有" to externalPrivate)
            }
            add("下载" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS))
            add("图片" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES))
            add("DCIM" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM))
            add("文档" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS))
            add("视频" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES))
            add("音乐" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC))
        }.filter { it.second.exists() }
    }

    private fun shortDirLabel(dir: File): String {
        val path = dir.absolutePath
        return when {
            path == defaultSharedRoot().absolutePath -> "内部存储"
            path == appPrivateRoot().absolutePath -> "应用私有"
            path == filesDir.absolutePath -> "files"
            path == cacheDir.absolutePath -> "cache"
            path == noBackupFilesDir.absolutePath -> "no_backup"
            getExternalFilesDir(null)?.absolutePath == path -> "外部私有"
            else -> dir.name.ifBlank { "/" }
        }
    }

    private fun mimeFor(file: File): String {
        val ext = file.extension.lowercase(Locale.ROOT)
        return when {
            ext in textExtensions -> "text/plain"
            ext in imageExtensions -> "image/*"
            ext in videoExtensions -> "video/*"
            ext in audioExtensions -> "audio/*"
            ext == "pdf" -> "application/pdf"
            ext in archiveExtensions -> "application/zip"
            else -> "*/*"
        }
    }

    private fun isArchiveFile(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in archiveExtensions
    }

    private fun isTextFile(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in textExtensions
    }

    private fun isAudioFile(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in audioExtensions
    }

    private fun isVideoFile(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in videoExtensions
    }

    private fun rounded(color: Int, radius: Int, strokeWidth: Int, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            if (strokeWidth > 0) {
                setStroke(dp(strokeWidth), strokeColor)
            }
        }
    }

    private fun chip(label: String, selected: Boolean, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = rounded(
                if (selected) 0xFF2F5F9F.toInt() else 0xFF242424.toInt(),
                16,
                1,
                if (selected) 0xFF6EA7FF.toInt() else 0xFF3A3A3A.toInt(),
            )
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(0, 0, dp(6), 0)
            }
        }
    }

    private fun tinyButton(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(5), dp(8), dp(5))
            background = rounded(0xFF252525.toInt(), 12, 1, 0xFF3A3A3A.toInt())
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(dp(5), 0, 0, 0)
            }
        }
    }

    private fun iconButton(icon: Int, action: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(icon)
            setColorFilter(Color.WHITE)
            background = rounded(0x00252525, 12, 0, 0)
            setPadding(dp(6), dp(6), dp(6), dp(6))
            setOnClickListener { action() }
        }
    }

    private fun typeIcon(directory: Boolean, fileName: String): TextView {
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        val label = when {
            directory -> "DIR"
            ext in imageExtensions -> "IMG"
            ext in videoExtensions -> "VID"
            ext in audioExtensions -> "AUD"
            ext in textExtensions -> "TXT"
            ext in archiveExtensions -> "ZIP"
            ext == "pdf" -> "PDF"
            else -> "FILE"
        }
        val color = when {
            directory -> 0xFF315A9C.toInt()
            ext in imageExtensions -> 0xFF2C7A55.toInt()
            ext in videoExtensions -> 0xFF7C3B82.toInt()
            ext in audioExtensions -> 0xFF8A5B2E.toInt()
            ext in textExtensions -> 0xFF3D6477.toInt()
            ext in archiveExtensions -> 0xFF7F5B1F.toInt()
            else -> 0xFF555555.toInt()
        }
        return TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 9f
            typeface = Typeface.DEFAULT_BOLD
            background = rounded(color, 10, 0, 0)
        }
    }

    private fun createListHolder(parent: ViewGroup): FileViewHolder {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }
        val icon = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(38), dp(38))
        }
        row.addView(icon)
        val textColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, 0, 0)
        }
        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            maxLines = 1
        }
        val meta = TextView(this).apply {
            setTextColor(0xFFAAAAAA.toInt())
            textSize = 11f
            maxLines = 2
        }
        textColumn.addView(title)
        textColumn.addView(meta)
        row.addView(
            textColumn,
            LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            ),
        )
        val params = RecyclerView.LayoutParams(
            RecyclerView.LayoutParams.MATCH_PARENT,
            RecyclerView.LayoutParams.WRAP_CONTENT,
        ).apply {
            bottomMargin = dp(6)
        }
        row.layoutParams = params
        return FileViewHolder(row, icon, title, meta)
    }

    private fun createGridHolder(parent: ViewGroup): FileViewHolder {
        val cell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), dp(10), dp(8), dp(8))
        }
        val icon = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(50), dp(50))
        }
        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            maxLines = 2
            gravity = Gravity.CENTER
        }
        val meta = TextView(this).apply {
            setTextColor(0xFF9A9A9A.toInt())
            textSize = 10f
            maxLines = 2
            gravity = Gravity.CENTER
        }
        cell.addView(icon)
        cell.addView(title)
        cell.addView(meta)
        val params = RecyclerView.LayoutParams(
            RecyclerView.LayoutParams.MATCH_PARENT,
            RecyclerView.LayoutParams.WRAP_CONTENT,
        ).apply {
            setMargins(dp(3), dp(3), dp(3), dp(3))
        }
        cell.layoutParams = params
        return FileViewHolder(cell, icon, title, meta)
    }

    private fun bindEntry(holder: FileViewHolder, entry: FileEntry, grid: Boolean) {
        val file = entry.file
        val selected = file != null && selectedPaths.contains(file.absolutePath)
        holder.title.text = entry.title
        holder.meta.text = entry.meta
        bindIcon(holder.icon, file, entry, grid)
        holder.itemView.background = rounded(
            if (selected) 0xFF244A7C.toInt() else 0xFF202020.toInt(),
            if (grid) 14 else 12,
            1,
            if (selected) 0xFF79B1FF.toInt() else 0xFF2F2F2F.toInt(),
        )
        holder.itemView.setOnClickListener {
            when {
                selectionMode && !entry.isParent && file != null -> toggleSelection(file)
                entry.isParent && file != null -> {
                    setActiveDir(file)
                    renderDirectoryState(forceReload = true)
                }
                entry.isDirectory && file != null -> {
                    setActiveDir(file)
                    renderDirectoryState(forceReload = true)
                }
                file != null -> openPreview(file)
            }
        }
        holder.itemView.setOnLongClickListener {
            when {
                entry.isParent || file == null -> false
                selectionMode -> {
                    toggleSelection(file)
                    true
                }
                else -> {
                    showItemMenu(holder.itemView, entry)
                    true
                }
            }
        }
        if (grid) {
            holder.title.gravity = Gravity.CENTER
            holder.meta.gravity = Gravity.CENTER
        } else {
            holder.title.gravity = Gravity.START
            holder.meta.gravity = Gravity.START
        }
    }

    private fun bindIcon(icon: TextView, file: File?, entry: FileEntry, grid: Boolean) {
        val size = if (grid) dp(50) else dp(38)
        icon.layoutParams = (icon.layoutParams as LinearLayout.LayoutParams).apply {
            width = size
            height = size
        }
        if (file != null && !entry.isDirectory && file.extension.lowercase(Locale.ROOT) in imageExtensions) {
            val thumb = loadThumbnail(file, size)
            if (thumb != null) {
                icon.text = ""
                icon.background = BitmapDrawable(resources, thumb)
                return
            }
        }
        val replacementIcon = typeIcon(entry.isDirectory, entry.title)
        icon.text = replacementIcon.text
        icon.gravity = Gravity.CENTER
        icon.setTextColor(replacementIcon.currentTextColor)
        icon.textSize = replacementIcon.textSize / resources.displayMetrics.scaledDensity
        icon.typeface = Typeface.DEFAULT_BOLD
        icon.background = replacementIcon.background
    }

    private fun loadThumbnail(file: File, size: Int): Bitmap? {
        val key = "${file.absolutePath}:${file.lastModified()}:$size"
        thumbnailCache.get(key)?.let { return it }
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            val sample = max(1, min(bounds.outWidth, bounds.outHeight) / max(1, size))
            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            BitmapFactory.decodeFile(file.absolutePath, options)?.also {
                thumbnailCache.put(key, it)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun toggleSelection(file: File) {
        if (selectedPaths.contains(file.absolutePath)) {
            selectedPaths.remove(file.absolutePath)
        } else {
            selectedPaths.add(file.absolutePath)
        }
        selectionMode = selectedPaths.isNotEmpty()
        bindPanelScaffold()
        fileAdapter?.notifyDataSetChanged()
    }

    private fun panelWidth(): Int {
        val width = resources.displayMetrics.widthPixels
        return min(width - dp(12), max(dp(320), width - dp(28)))
    }

    private fun panelHeight(): Int {
        val height = resources.displayMetrics.heightPixels
        return min(height - dp(40), max(dp(420), (height * 0.72f).toInt()))
    }

    private fun gridSpanCount(): Int {
        return if (panelWidth() >= dp(470)) 3 else 2
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun formatSize(bytes: Long): String {
        if (bytes < 0) return "?"
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.ROOT, "%.1f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.ROOT, "%.1f MB", mb)
        return String.format(Locale.ROOT, "%.1f GB", mb / 1024.0)
    }

    private fun formatDate(time: Long): String {
        return SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).format(Date(time))
    }

    private fun uniqueDestination(parent: File, name: String): File {
        var candidate = File(parent, name)
        if (!candidate.exists()) {
            return candidate
        }
        val base = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var index = 1
        while (candidate.exists()) {
            val nextName = if (ext.isEmpty() || base == name && !name.contains('.')) {
                "$base ($index)"
            } else {
                "$base ($index).$ext"
            }
            candidate = File(parent, nextName)
            index++
        }
        return candidate
    }

    private fun ensureZipFileName(name: String): String {
        val trimmed = name.trim().ifBlank { "archive" }
        return if (trimmed.lowercase(Locale.ROOT).endsWith(".zip")) trimmed else "$trimmed.zip"
    }

    private fun countPathUnits(path: File): Int {
        if (!path.exists()) {
            return 0
        }
        if (!path.isDirectory) {
            return 1
        }
        val children = path.listFiles().orEmpty()
        return 1 + children.sumOf { countPathUnits(it) }
    }

    private fun countArchiveEntries(archive: File): Int {
        return try {
            ZipFile(archive).use { zip -> zip.size() }
        } catch (_: Exception) {
            0
        }
    }

    private fun copyPath(source: File, destination: File, onStep: (Int, String) -> Unit = { _, _ -> }) {
        if (source.isDirectory) {
            if (!destination.exists() && !destination.mkdirs()) {
                throw IllegalStateException("无法创建目录 ${destination.name}")
            }
            onStep(1, destination.name)
            source.listFiles()?.forEach { child ->
                copyPath(child, File(destination, child.name), onStep)
            }
            return
        }
        destination.parentFile?.mkdirs()
        FileInputStream(source).use { input ->
            FileOutputStream(destination).use { output ->
                input.copyTo(output)
            }
        }
        destination.setLastModified(source.lastModified())
        onStep(1, destination.name)
    }

    private fun movePath(source: File, destination: File, onStep: (Int, String) -> Unit = { _, _ -> }) {
        val units = countPathUnits(source).coerceAtLeast(1)
        destination.parentFile?.mkdirs()
        if (source.renameTo(destination)) {
            onStep(units, destination.name)
            return
        }
        copyPath(source, destination, onStep)
        deletePath(source)
    }

    private fun deletePath(path: File, onStep: (Int, String) -> Unit = { _, _ -> }) {
        if (path.isDirectory) {
            path.listFiles()?.forEach { deletePath(it, onStep) }
        }
        if (!path.delete() && path.exists()) {
            throw IllegalStateException("无法删除 ${path.name}")
        }
        onStep(1, path.name)
    }

    private fun unzipToDirectory(
        archive: File,
        targetRoot: File,
        onStep: (Int, String) -> Unit = { _, _ -> },
    ) {
        if (!targetRoot.exists() && !targetRoot.mkdirs()) {
            throw IllegalStateException("无法创建解压目录")
        }
        ZipInputStream(FileInputStream(archive)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val target = File(targetRoot, entry.name).canonicalFile
                val canonicalRoot = targetRoot.canonicalFile
                if (!target.path.startsWith(canonicalRoot.path)) {
                    throw IllegalStateException("压缩包包含非法路径")
                }
                if (entry.isDirectory) {
                    if (!target.exists() && !target.mkdirs()) {
                        throw IllegalStateException("无法创建目录 ${target.name}")
                    }
                } else {
                    target.parentFile?.mkdirs()
                    FileOutputStream(target).use { output ->
                        zip.copyTo(output)
                    }
                }
                onStep(1, entry.name)
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }
    }

    private fun zipPaths(
        target: File,
        sources: List<File>,
        onStep: (Int, String) -> Unit = { _, _ -> },
    ) {
        target.parentFile?.mkdirs()
        ZipOutputStream(FileOutputStream(target)).use { zip ->
            sources.forEach { source ->
                addToZip(zip, source, source.name, onStep)
            }
        }
    }

    private fun addToZip(
        zip: ZipOutputStream,
        source: File,
        entryName: String,
        onStep: (Int, String) -> Unit,
    ) {
        val normalizedName = entryName.replace(File.separatorChar, '/')
        if (source.isDirectory) {
            val dirEntryName = normalizedName.trimEnd('/') + "/"
            val dirEntry = ZipEntry(dirEntryName).apply {
                time = source.lastModified()
            }
            zip.putNextEntry(dirEntry)
            zip.closeEntry()
            onStep(1, dirEntryName)
            source.listFiles()?.forEach { child ->
                addToZip(zip, child, "$dirEntryName${child.name}", onStep)
            }
            return
        }

        val entry = ZipEntry(normalizedName).apply {
            time = source.lastModified()
        }
        zip.putNextEntry(entry)
        FileInputStream(source).use { input ->
            input.copyTo(zip)
        }
        zip.closeEntry()
        onStep(1, normalizedName)
    }

    private inner class CodeEditorEditText(context: Context) : EditText(context) {
        private val gutterBackgroundPaint = Paint().apply {
            color = 0xFF0F131A.toInt()
        }
        private val gutterDividerPaint = Paint().apply {
            color = 0xFF2F3A4A.toInt()
            strokeWidth = dp(1).toFloat()
        }
        private val lineNumberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF7F8DA3.toInt()
            textAlign = Paint.Align.RIGHT
            textSize = sp(10f)
            typeface = Typeface.MONOSPACE
        }
        private var applyingHighlight = false
        private val highlightRunnable = Runnable {
            applySyntaxHighlighting()
            invalidate()
        }

        init {
            setTextColor(Color.WHITE)
            setHintTextColor(0xFF888888.toInt())
            setBackgroundColor(Color.BLACK)
            textSize = 12f
            typeface = Typeface.MONOSPACE
            gravity = Gravity.TOP or Gravity.START
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            setHorizontallyScrolling(true)
            setPadding(gutterWidth() + dp(12), dp(12), dp(18), dp(12))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit

                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    setPadding(gutterWidth() + dp(12), dp(12), dp(18), dp(12))
                    removeCallbacks(highlightRunnable)
                    postDelayed(highlightRunnable, 70L)
                }

                override fun afterTextChanged(s: Editable?) = Unit
            })
        }

        override fun onDraw(canvas: Canvas) {
            val gutterRight = totalPaddingLeft - dp(10)
            canvas.drawRect(
                0f,
                scrollY.toFloat(),
                gutterRight.toFloat(),
                (scrollY + height).toFloat(),
                gutterBackgroundPaint,
            )
            canvas.drawLine(
                gutterRight.toFloat(),
                scrollY.toFloat(),
                gutterRight.toFloat(),
                (scrollY + height).toFloat(),
                gutterDividerPaint,
            )
            layout?.let { textLayout ->
                val firstLine = textLayout.getLineForVertical(scrollY)
                val lastLine = textLayout.getLineForVertical(scrollY + height)
                val currentLine = textLayout.getLineForOffset(selectionStart.coerceAtLeast(0))
                for (line in firstLine..lastLine) {
                    val baseline = textLayout.getLineBaseline(line) + totalPaddingTop
                    lineNumberPaint.color =
                        if (line == currentLine) 0xFF9FC3FF.toInt() else 0xFF7F8DA3.toInt()
                    canvas.drawText(
                        (line + 1).toString(),
                        (gutterRight - dp(6)).toFloat(),
                        baseline.toFloat(),
                        lineNumberPaint,
                    )
                }
            }
            super.onDraw(canvas)
        }

        private fun gutterWidth(): Int {
            val digits = max(2, lineCount.coerceAtLeast(1).toString().length)
            val sampleWidth = lineNumberPaint.measureText("9".repeat(digits)).roundToInt()
            return max(dp(42), sampleWidth + dp(18))
        }

        private fun applySyntaxHighlighting() {
            if (applyingHighlight) {
                return
            }
            val editable = text ?: return
            if (editable.length > MAX_HIGHLIGHT_LENGTH) {
                editable.getSpans(0, editable.length, SyntaxColorSpan::class.java).forEach(editable::removeSpan)
                return
            }
            applyingHighlight = true
            editable.getSpans(0, editable.length, SyntaxColorSpan::class.java).forEach(editable::removeSpan)
            val content = editable.toString()
            applyPattern(editable, content, COMMENT_BLOCK_PATTERN, 0xFF6A9955.toInt())
            applyPattern(editable, content, COMMENT_LINE_PATTERN, 0xFF6A9955.toInt())
            applyPattern(editable, content, STRING_PATTERN, 0xFFCE9178.toInt())
            applyPattern(editable, content, NUMBER_PATTERN, 0xFFB5CEA8.toInt())
            applyPattern(editable, content, KEYWORD_PATTERN, 0xFF569CD6.toInt())
            applyPattern(editable, content, ANNOTATION_PATTERN, 0xFFDCDCAA.toInt())
            applyingHighlight = false
        }

        private fun applyPattern(editable: Editable, source: String, regex: Regex, color: Int) {
            regex.findAll(source).forEach { match ->
                editable.setSpan(
                    SyntaxColorSpan(color),
                    match.range.first,
                    match.range.last + 1,
                    android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        }
    }

    private class SyntaxColorSpan(color: Int) : ForegroundColorSpan(color)

    private fun sp(value: Float): Float = value * resources.displayMetrics.scaledDensity

    private inner class FileListAdapter : RecyclerView.Adapter<FileViewHolder>() {
        private var entries: List<FileEntry> = emptyList()
        private var mode: ViewMode = ViewMode.LIST

        fun submitList(items: List<FileEntry>) {
            entries = items
            notifyDataSetChanged()
        }

        fun setViewMode(nextMode: ViewMode) {
            if (mode == nextMode) {
                return
            }
            mode = nextMode
            notifyDataSetChanged()
        }

        override fun getItemCount(): Int = entries.size

        override fun getItemViewType(position: Int): Int {
            return if (mode == ViewMode.GRID) 1 else 0
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FileViewHolder {
            return if (viewType == 1) createGridHolder(parent) else createListHolder(parent)
        }

        override fun onBindViewHolder(holder: FileViewHolder, position: Int) {
            bindEntry(holder, entries[position], mode == ViewMode.GRID)
        }
    }

    private class FileViewHolder(
        itemView: View,
        val icon: TextView,
        val title: TextView,
        val meta: TextView,
    ) : RecyclerView.ViewHolder(itemView)

    private data class FileEntry(
        val title: String,
        val meta: String,
        val file: File?,
        val isDirectory: Boolean,
        val isParent: Boolean,
    )

    private data class FileTab(
        val id: Int,
        var title: String,
        var currentDir: File,
        var entries: List<FileEntry> = emptyList(),
        var lastRequestId: Int = 0,
        var pinned: Boolean = false,
    )

    private data class ClipboardState(
        val files: List<File>,
        val move: Boolean,
    )

    private enum class ViewMode {
        LIST,
        GRID,
    }

    private enum class SortMode(val label: String) {
        NAME("按名称"),
        DATE("按时间"),
        SIZE("按大小"),
        TYPE("按类型");

        fun next(): SortMode {
            val values = values()
            return values[(ordinal + 1) % values.size]
        }
    }

    companion object {
        private const val NOTIFICATION_ID = 7071
        private const val MAX_TABS = 6
        private const val MAX_RECENT_DIRS = 12
        private const val MAX_HIGHLIGHT_LENGTH = 220_000
        private const val PREFS_NAME = "floating_file_manager"
        private const val KEY_FAVORITES = "favorite_dirs"
        private const val KEY_RECENTS = "recent_dirs"

        private val KEYWORD_PATTERN = Regex(
            "\\b(?:class|fun|val|var|if|else|for|while|return|import|package|public|private|protected|static|final|void|int|long|double|float|boolean|true|false|null|def|from|as|const|let|function|async|await|switch|case|break|continue|try|catch|finally|new|this|super|extends|implements|interface|enum|typedef|sealed|when|object|override|struct|namespace|using|throw|throws|yield|lambda)\\b",
        )
        private val STRING_PATTERN = Regex("\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'")
        private val NUMBER_PATTERN = Regex("\\b\\d+(?:\\.\\d+)?\\b")
        private val ANNOTATION_PATTERN = Regex("@[A-Za-z_][A-Za-z0-9_]*")
        private val COMMENT_LINE_PATTERN = Regex("//.*?$|#.*?$", setOf(RegexOption.MULTILINE))
        private val COMMENT_BLOCK_PATTERN = Regex("/\\*.*?\\*/", setOf(RegexOption.DOT_MATCHES_ALL))

        @Volatile
        var running: Boolean = false
            private set

        private val textExtensions = setOf(
            "txt", "md", "json", "xml", "html", "htm", "css", "js", "ts",
            "dart", "kt", "java", "py", "sh", "log", "yaml", "yml", "toml",
            "ini", "conf", "csv", "properties", "gradle",
        )
        private val imageExtensions = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp")
        private val videoExtensions = setOf("mp4", "mkv", "webm", "3gp", "mov", "avi")
        private val audioExtensions = setOf("mp3", "m4a", "aac", "wav", "ogg", "flac")
        private val archiveExtensions = setOf("zip", "apk", "jar")

        fun start(context: Context) {
            val intent = Intent(context, FloatingFileManagerService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FloatingFileManagerService::class.java))
        }
    }
}
