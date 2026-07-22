package com.agent.cyx

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
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
    private var controlBarExpanded = false
    private var selectionMode = false
    private val selectedPaths = LinkedHashSet<String>()
    private var clipboard: ClipboardState? = null

    private var titleView: TextView? = null
    private var backButton: ImageButton? = null
    private var saveButton: ImageButton? = null
    private var openButton: ImageButton? = null
    private var shareButton: ImageButton? = null
    private var extractButton: ImageButton? = null
    private var minimizeButton: ImageButton? = null
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
        tab.scrollPosition = 0
        tab.scrollOffset = 0
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
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = rounded(0xFF121A24.toInt(), 18, 1, 0xFF334557.toInt())
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 0, 0, 0)
            }
            tabsRow = row
            addView(row)
        }
        tabsScroll = tabScroll
        panel.addView(
            tabScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            },
        )

        val rootsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setPadding(dp(6), dp(4), dp(6), dp(6))
            background = rounded(0xFF101821.toInt(), 18, 1, 0xFF2B4155.toInt())
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 0, 0, 0)
            }
            quickRootsRow = row
            addView(row)
        }
        quickRootsScroll = rootsScroll
        panel.addView(
            rootsScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            },
        )

        val crumbScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setPadding(dp(6), dp(4), dp(6), dp(6))
            background = rounded(0xFF10161D.toInt(), 18, 1, 0xFF31485D.toInt())
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 0, 0, 0)
            }
            breadcrumbRow = row
            addView(row)
        }
        breadcrumbScroll = crumbScroll
        panel.addView(
            crumbScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            },
        )

        val controlsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setPadding(dp(2), 0, dp(2), dp(8))
            background = rounded(0xFF121A22.toInt(), 18, 1, 0xFF2F3C4B.toInt())
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(8), dp(8), dp(8))
            }
            controlBarRow = row
            addView(row)
        }
        controlBarScroll = controlsScroll
        panel.addView(
            controlsScroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            },
        )

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
            ).apply {
                topMargin = dp(8)
            },
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
            setPadding(dp(8), dp(8), dp(8), dp(10))
            background = rounded(0xFF121A22.toInt(), 20, 1, 0xFF2E3948.toInt())
        }
        attachDrag(toolbar)

        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
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

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val back = toolbarActionButton(toolbarBackIcon(), "上级") {
            if (previewing) {
                closePreview()
            } else {
                goParent()
            }
        }
        val save = toolbarActionButton(R.drawable.lucide_save, "保存") { saveCurrentTextFile() }
        val open = toolbarActionButton(R.drawable.lucide_eye, "打开") { currentPreviewFile?.let { openExternal(it) } }
        val share = toolbarActionButton(R.drawable.lucide_upload, "分享") { currentPreviewFile?.let { shareFile(it) } }
        val extract = toolbarActionButton(R.drawable.lucide_upload, "解压") {
            currentPreviewFile?.let { extractArchiveToCurrentDir(it) }
        }
        val minimize = toolbarActionButton(R.drawable.lucide_x, "最小化") { showMinimizedBubble() }
        val close = toolbarActionButton(R.drawable.lucide_x, "关闭") { stopSelf() }
        backButton = back
        saveButton = save
        openButton = open
        shareButton = share
        extractButton = extract
        minimizeButton = minimize

        actionRow.addView(back)
        actionRow.addView(save)
        actionRow.addView(open)
        actionRow.addView(share)
        actionRow.addView(extract)
        actionRow.addView(minimize)
        actionRow.addView(close)
        toolbar.addView(
            HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                addView(actionRow)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        return toolbar
    }

    private fun bindPanelScaffold() {
        val tab = activeTab()
        titleView?.text = if (previewing) {
            currentPreviewFile?.name ?: "预览"
        } else {
            "${tab.title} · ${tab.currentDir.absolutePath}"
        }

        backButton?.setImageResource(toolbarBackIcon())
        backButton?.contentDescription = if (previewing) "返回" else "上级"
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
            box.addView(ImageView(this).apply {
                setImageResource(R.drawable.lucide_x)
                setColorFilter(0xFFD6E7FF.toInt())
                setPadding(dp(6), 0, 0, 0)
                layoutParams = LinearLayout.LayoutParams(dp(16), dp(16))
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
        row.addView(
            controlActionButton(
                icon = if (controlBarExpanded) R.drawable.lucide_eye_off else R.drawable.lucide_eye,
                label = if (controlBarExpanded) "收起" else "选项",
                selected = controlBarExpanded,
                expanded = true,
            ) {
                controlBarExpanded = !controlBarExpanded
                rebuildControlBar()
            },
        )
        if (selectionMode) {
            row.addView(controlActionButton(R.drawable.lucide_eye, "已选 ${selectedPaths.size}", true, controlBarExpanded) {})
            row.addView(controlActionButton(R.drawable.lucide_copy, "全选", false, controlBarExpanded) { selectAllVisible() })
            if (selectedPaths.size == 1) {
                row.addView(controlActionButton(R.drawable.lucide_square_pen, "重命名", false, controlBarExpanded) { renameSelected() })
            }
            row.addView(controlActionButton(R.drawable.lucide_upload, "压缩", false, controlBarExpanded) { compressFilesPrompt(selectedFiles()) })
            row.addView(controlActionButton(R.drawable.lucide_copy, "复制", false, controlBarExpanded) { captureClipboard(move = false) })
            row.addView(controlActionButton(R.drawable.lucide_chevron_left, "移动", false, controlBarExpanded) { captureClipboard(move = true) })
            row.addView(controlActionButton(R.drawable.lucide_trash_2, "删除", false, controlBarExpanded) { deleteSelected() })
            row.addView(controlActionButton(R.drawable.lucide_x, "取消", false, controlBarExpanded) { clearSelection() })
            return
        }

        clipboard?.let {
            row.addView(
                controlActionButton(
                    R.drawable.lucide_clipboard_paste,
                    if (it.move) "粘贴移动" else "粘贴复制",
                    true,
                    controlBarExpanded,
                ) { pasteClipboard() },
            )
        }
        val currentDir = activeTab().currentDir
        row.addView(controlActionButton(R.drawable.lucide_star, if (isFavoriteDir(currentDir)) "取消收藏" else "收藏当前", isFavoriteDir(currentDir), controlBarExpanded) {
            toggleFavoriteDir(currentDir)
        })
        val favoritesChip = controlActionButton(R.drawable.lucide_star, "收藏夹", favoriteDirs.isNotEmpty(), controlBarExpanded) {}
        favoritesChip.setOnClickListener {
            showDirectoryCollectionMenu(
                anchor = favoritesChip,
                title = "收藏夹为空",
                directories = favoriteDirectoryFiles(),
            )
        }
        row.addView(favoritesChip)
        val recentChip = controlActionButton(R.drawable.lucide_refresh_cw, "最近", recentDirs.isNotEmpty(), controlBarExpanded) {}
        recentChip.setOnClickListener {
            showDirectoryCollectionMenu(
                anchor = recentChip,
                title = "最近目录为空",
                directories = recentDirectoryFiles(),
                allowClear = true,
            )
        }
        row.addView(recentChip)
        row.addView(controlActionButton(R.drawable.lucide_plus, "新建", false, controlBarExpanded) { createFolderPrompt() })
        row.addView(controlActionButton(R.drawable.lucide_copy, "多选", false, controlBarExpanded) {
            selectionMode = true
            bindPanelScaffold()
            fileAdapter?.notifyDataSetChanged()
        })
        row.addView(controlActionButton(R.drawable.lucide_layout_list, if (viewMode == ViewMode.LIST) "列表" else "网格", true, controlBarExpanded) {
            viewMode = if (viewMode == ViewMode.LIST) ViewMode.GRID else ViewMode.LIST
            fileAdapter?.setViewMode(viewMode)
            updateLayoutManager()
        })
        row.addView(controlActionButton(R.drawable.lucide_refresh_cw, sortMode.label, false, controlBarExpanded) {
            sortMode = sortMode.next()
            renderDirectoryState(forceReload = true)
        })
        row.addView(controlActionButton(if (showHidden) R.drawable.lucide_eye else R.drawable.lucide_eye_off, if (showHidden) "隐藏:开" else "隐藏:关", showHidden, controlBarExpanded) {
            showHidden = !showHidden
            renderDirectoryState(forceReload = true)
        })
        row.addView(controlActionButton(R.drawable.lucide_refresh_cw, "刷新", false, controlBarExpanded) { renderDirectoryState(forceReload = true) })
    }

    private fun updateLayoutManager() {
        val recycler = recyclerView ?: return
        val current = recycler.layoutManager
        val canReuse = when (viewMode) {
            ViewMode.LIST -> current is LinearLayoutManager && current !is GridLayoutManager
            ViewMode.GRID -> current is GridLayoutManager && current.spanCount == gridSpanCount()
        }
        if (canReuse) {
            return
        }
        saveActiveScrollState()
        recycler.layoutManager = when (viewMode) {
            ViewMode.LIST -> LinearLayoutManager(this)
            ViewMode.GRID -> GridLayoutManager(this, gridSpanCount())
        }
        restoreActiveScrollState()
    }

    private fun saveActiveScrollState() {
        val recycler = recyclerView ?: return
        val manager = recycler.layoutManager as? LinearLayoutManager ?: return
        val position = manager.findFirstVisibleItemPosition()
        if (position == RecyclerView.NO_POSITION) {
            return
        }
        val firstView = manager.findViewByPosition(position)
        val offset = (firstView?.top ?: recycler.paddingTop) - recycler.paddingTop
        activeTab().scrollPosition = position
        activeTab().scrollOffset = offset
    }

    private fun restoreActiveScrollState() {
        val recycler = recyclerView ?: return
        val tab = activeTab()
        if (tab.entries.isEmpty()) {
            return
        }
        val position = tab.scrollPosition.coerceIn(0, tab.entries.lastIndex)
        val offset = tab.scrollOffset
        recycler.post {
            val manager = recycler.layoutManager as? LinearLayoutManager ?: return@post
            manager.scrollToPositionWithOffset(position, offset)
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
            restoreActiveScrollState()
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
                    restoreActiveScrollState()
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
        saveActiveScrollState()
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
        val editor = CodeEditorEditText(this).apply {
            currentTextEditor = this
            setText(text)
            setSelection(text.length.coerceAtMost(length()))
        }
        val cursorStatus = TextView(this).apply {
            setTextColor(TEXT_MUTED_COLOR)
            textSize = 11f
            setPadding(dp(10), dp(8), dp(10), dp(8))
            this.text = editor.cursorLabel()
        }
        fun refreshCursorStatus() {
            cursorStatus.text = editor.cursorLabel()
        }
        editor.setCursorStatusListener { refreshCursorStatus() }

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            addView(
                HorizontalScrollView(context).apply {
                    isHorizontalScrollBarEnabled = false
                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            setPadding(dp(10), dp(10), dp(10), dp(6))
                            addView(chip("查找", false) {
                                showTextInputDialog("查找文本", "输入关键词", "") { query ->
                                    if (!editor.findNext(query)) {
                                        Toast.makeText(this@FloatingFileManagerService, "未找到: $query", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            })
                            addView(chip("跳行", false) {
                                showTextInputDialog("跳转到行", "输入行号", "1") { input ->
                                    val line = input.toIntOrNull()
                                    if (line == null || !editor.jumpToLine(line)) {
                                        Toast.makeText(this@FloatingFileManagerService, "行号无效", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            })
                            addView(chip("插入Tab", false) { editor.insertAtCursor("    ") })
                            addView(chip("全选", false) { editor.selectAll() })
                            addView(chip("换行", false) {
                                editor.toggleWrap()
                                Toast.makeText(
                                    this@FloatingFileManagerService,
                                    if (editor.wrapEnabled) "已开启自动换行" else "已切换为横向滚动",
                                    Toast.LENGTH_SHORT,
                                ).show()
                            })
                            addView(chip("复制路径", false) { copyTextToClipboard("文件路径", file.absolutePath) })
                        },
                    )
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(cursorStatus)
            addView(
                ScrollView(context).apply {
                    addView(editor)
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    0,
                    1f,
                ),
            )
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
        val info = readImageInfo(file)
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            setBackgroundColor(Color.BLACK)
        }
        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(CARD_SURFACE_COLOR, 18, 1, CARD_BORDER_COLOR)
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        hero.addView(TextView(this).apply {
            text = file.name
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 2
        })
        hero.addView(TextView(this).apply {
            text = buildString {
                append("${info.width} × ${info.height}")
                info.mimeType?.takeIf { it.isNotBlank() }?.let {
                    append(" · ")
                    append(it.substringAfter('/').uppercase(Locale.ROOT))
                }
                append(" · ")
                append(formatSize(file.length()))
            }
            setTextColor(TEXT_SECONDARY_COLOR)
            textSize = 12f
            setPadding(0, dp(6), 0, 0)
            maxLines = 2
        })
        container.addView(hero)

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, dp(10))
        }
        actionRow.addView(chip("图片信息", false) { showImageInfoDialog(file) })
        if (canTransformImage(file)) {
            actionRow.addView(chip("旋转 90°", false) { rotateImagePrompt(file) })
            actionRow.addView(chip("水平镜像", false) { mirrorImagePrompt(file) })
            actionRow.addView(chip("导出 JPG", false) { exportImagePrompt(file, ImageExportFormat.JPG) })
            actionRow.addView(chip("导出 WEBP", false) { exportImagePrompt(file, ImageExportFormat.WEBP) })
        }
        container.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(actionRow)
        })

        container.addView(
            FrameLayout(this).apply {
                background = rounded(0xFF10161F.toInt(), 18, 1, 0xFF263243.toInt())
                addView(
                    ImageView(context).apply {
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        adjustViewBounds = true
                        setImageURI(Uri.fromFile(file))
                    },
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        Gravity.CENTER,
                    ),
                )
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        return container
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
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(0xFF172437.toInt(), 0xFF0F151D.toInt(), 0xFF1D1627.toInt()),
            ).apply {
                cornerRadius = dp(24).toFloat()
                setStroke(dp(1), 0xFF31465D.toInt())
            }
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val coverFrame = FrameLayout(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0xFF263D58.toInt(), 0xFF121A25.toInt()),
            ).apply {
                cornerRadius = dp(22).toFloat()
                setStroke(dp(1), 0xFF5E7DA0.toInt())
            }
            elevation = dp(3).toFloat()
        }
        val coverSize = dp(118)
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
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    addView(ImageView(context).apply {
                        setImageResource(R.drawable.lucide_play)
                        setColorFilter(0xFFDCEAFF.toInt())
                        scaleType = ImageView.ScaleType.FIT_CENTER
                    }, LinearLayout.LayoutParams(dp(52), dp(52)))
                    addView(TextView(context).apply {
                        text = file.extension.uppercase(Locale.ROOT).ifBlank { "AUDIO" }
                        gravity = Gravity.CENTER
                        setTextColor(0xFF9DB6D8.toInt())
                        textSize = 12f
                        typeface = Typeface.DEFAULT_BOLD
                    })
                },
                FrameLayout.LayoutParams(coverSize, coverSize, Gravity.CENTER),
            )
        }
        topRow.addView(
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
        topRow.addView(
            infoColumn,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        hero.addView(topRow)

        hero.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.BOTTOM
                setPadding(0, dp(18), 0, dp(4))
                val heights = intArrayOf(14, 30, 20, 44, 24, 36, 18, 50, 28, 40, 22, 34, 16, 46, 26, 38)
                heights.forEachIndexed { index, height ->
                    addView(
                        View(context).apply {
                            background = rounded(
                                if (index % 3 == 0) 0xFF69A7FF.toInt() else 0xFFB9D6FF.toInt(),
                                8,
                                0,
                                0,
                            )
                            alpha = if (index % 2 == 0) 0.9f else 0.55f
                        },
                        LinearLayout.LayoutParams(0, dp(height), 1f).apply {
                            setMargins(dp(2), 0, dp(2), 0)
                        },
                    )
                }
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(hero)

        val metaPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(0xFF101821.toInt(), 18, 1, 0xFF263648.toInt())
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        metaPanel.addView(TextView(this).apply {
            text = "音频信息"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
        })
        val metaRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(10), 0, 0)
        }
        fun addMeta(label: String, value: String) {
            metaRow.addView(
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    background = rounded(0xFF17212C.toInt(), 14, 1, 0xFF314154.toInt())
                    setPadding(dp(10), dp(8), dp(10), dp(8))
                    addView(TextView(context).apply {
                        text = label
                        setTextColor(TEXT_MUTED_COLOR)
                        textSize = 10f
                    })
                    addView(TextView(context).apply {
                        text = value
                        setTextColor(Color.WHITE)
                        textSize = 12f
                        typeface = Typeface.DEFAULT_BOLD
                        maxLines = 1
                    })
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    setMargins(0, 0, dp(8), 0)
                },
            )
        }
        addMeta("时长", info?.durationMs?.takeIf { it > 0 }?.let(MediaToolbox::formatDuration) ?: "--:--")
        addMeta("码率", info?.bitrate?.takeIf { it > 0 }?.let { "${it / 1000} kbps" } ?: "未知")
        addMeta("采样率", info?.sampleRate?.takeIf { it > 0 }?.let { "${it} Hz" } ?: "未知")
        addMeta("大小", formatSize(file.length()))
        metaPanel.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(metaRow)
        })
        container.addView(
            metaPanel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(12)
            },
        )

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, dp(8))
        }
        actionRow.addView(chip("媒体信息", false) { showMediaInfoDialog(file) })
        if (file.extension.lowercase(Locale.ROOT) != "mp3") {
            actionRow.addView(chip("转 MP3", false) { convertAudioToMp3Prompt(file) })
        }
        if (file.extension.lowercase(Locale.ROOT) != "m4a") {
            actionRow.addView(chip("转 M4A", false) { convertAudioToM4aPrompt(file) })
        }
        actionRow.addView(chip("外部打开", false) { openExternal(file) })
        actionRow.addView(chip("分享", false) { shareFile(file) })
        container.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(actionRow)
        })

        val controlView = PlayerControlView(this).apply {
            setPlayer(player)
            setShowTimeoutMs(0)
            setShowNextButton(false)
            setShowPreviousButton(false)
            setShowShuffleButton(false)
            background = rounded(0xFF111820.toInt(), 18, 1, 0xFF2D4055.toInt())
            setPadding(dp(8), dp(6), dp(8), dp(6))
        }
        container.addView(
            controlView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(6)
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
                HorizontalScrollView(this).apply {
                    isHorizontalScrollBarEnabled = false
                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            setPadding(dp(12), dp(10), dp(12), dp(12))
                            addView(chip("媒体信息", false) { showMediaInfoDialog(file) })
                            addView(chip("提取音频", false) { extractAudioFromVideoPrompt(file) })
                            addView(chip("转 MP4", false) { convertVideoToMp4Prompt(file) })
                            addView(chip("截取封面", false) { extractVideoFramePrompt(file) })
                        },
                    )
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

    private fun copyTextToClipboard(label: String, value: String) {
        val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        manager.setPrimaryClip(ClipData.newPlainText(label, value))
        Toast.makeText(this, "已复制到剪贴板", Toast.LENGTH_SHORT).show()
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

    private fun showImageInfoDialog(file: File) {
        val info = readImageInfo(file)
        val text = buildString {
            appendLine("文件: ${file.name}")
            appendLine("分辨率: ${info.width} × ${info.height}")
            info.mimeType?.takeIf { it.isNotBlank() }?.let { appendLine("类型: $it") }
            appendLine("大小: ${formatSize(file.length())}")
            appendLine("修改时间: ${formatDate(file.lastModified())}")
            append("路径: ${file.absolutePath}")
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle("图片信息")
            .setMessage(text)
            .setPositiveButton("确定", null)
            .create()
        dialog.window?.setType(overlayType())
        dialog.show()
    }

    private fun rotateImagePrompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}-rotated.${file.extension.ifBlank { "png" }}"
        showTextInputDialog("旋转图片", "输出文件名", defaultName) { input ->
            val suffix = file.extension.ifBlank { "png" }
            val normalized = if (input.contains('.')) input else "$input.$suffix"
            val target = uniqueDestination(activeTab().currentDir, normalized)
            transformImageFile(file, target, "正在旋转图片...") { source ->
                Bitmap.createBitmap(
                    source,
                    0,
                    0,
                    source.width,
                    source.height,
                    Matrix().apply { postRotate(90f) },
                    true,
                )
            }
        }
    }

    private fun mirrorImagePrompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}-mirror.${file.extension.ifBlank { "png" }}"
        showTextInputDialog("镜像图片", "输出文件名", defaultName) { input ->
            val suffix = file.extension.ifBlank { "png" }
            val normalized = if (input.contains('.')) input else "$input.$suffix"
            val target = uniqueDestination(activeTab().currentDir, normalized)
            transformImageFile(file, target, "正在镜像图片...") { source ->
                Bitmap.createBitmap(
                    source,
                    0,
                    0,
                    source.width,
                    source.height,
                    Matrix().apply { preScale(-1f, 1f) },
                    true,
                )
            }
        }
    }

    private fun exportImagePrompt(file: File, format: ImageExportFormat) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}.${format.extension}"
        showTextInputDialog("导出 ${format.label}", "输出文件名", defaultName) { input ->
            val normalized = if (input.lowercase(Locale.ROOT).endsWith(".${format.extension}")) {
                input
            } else {
                "$input.${format.extension}"
            }
            val target = uniqueDestination(activeTab().currentDir, normalized)
            exportImageFile(file, target, format)
        }
    }

    private fun transformImageFile(
        source: File,
        target: File,
        progressText: String,
        transformer: (Bitmap) -> Bitmap,
    ) {
        showLoading(progressText)
        worker.execute {
            val result = runCatching {
                val input = BitmapFactory.decodeFile(source.absolutePath)
                    ?: error("无法读取图片")
                val output = transformer(input)
                saveBitmapToFile(output, target)
                if (output !== input) {
                    output.recycle()
                }
                input.recycle()
            }
            mainHandler.post {
                hideOperationProgress()
                if (result.isSuccess) {
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "已生成 ${target.name}", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(
                        this,
                        "图片处理失败: ${result.exceptionOrNull()?.message}",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun exportImageFile(source: File, target: File, format: ImageExportFormat) {
        showLoading("正在导出图片...")
        worker.execute {
            val result = runCatching {
                val input = BitmapFactory.decodeFile(source.absolutePath)
                    ?: error("无法读取图片")
                saveBitmapToFile(input, target, format)
                input.recycle()
            }
            mainHandler.post {
                hideOperationProgress()
                if (result.isSuccess) {
                    renderDirectoryState(forceReload = true)
                    Toast.makeText(this, "已导出 ${target.name}", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(
                        this,
                        "导出失败: ${result.exceptionOrNull()?.message}",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    private fun saveBitmapToFile(bitmap: Bitmap, target: File, format: ImageExportFormat? = null) {
        val exportFormat = format ?: ImageExportFormat.fromFile(target)
        target.parentFile?.mkdirs()
        FileOutputStream(target).use { output ->
            val ok = bitmap.compress(exportFormat.compressFormat(), exportFormat.quality, output)
            if (!ok) {
                throw IllegalStateException("Bitmap 压缩失败")
            }
        }
    }

    private fun readImageInfo(file: File): ImageInfo {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(file.absolutePath, options)
        return ImageInfo(
            width = options.outWidth.coerceAtLeast(0),
            height = options.outHeight.coerceAtLeast(0),
            mimeType = options.outMimeType,
        )
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

    private fun convertAudioToM4aPrompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}.m4a"
        showTextInputDialog("转为 M4A", "输出文件名", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, if (input.endsWith(".m4a", true)) input else "$input.m4a")
            showLoading("FFmpeg 正在转码音频...")
            worker.execute {
                val result = MediaToolbox.convertAudioToM4a(file, target)
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

    private fun convertVideoToMp4Prompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}.mp4"
        showTextInputDialog("转为 MP4", "输出文件名", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, if (input.endsWith(".mp4", true)) input else "$input.mp4")
            showLoading("FFmpeg 正在转码视频...")
            worker.execute {
                val result = MediaToolbox.convertVideoToMp4(file, target)
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

    private fun extractVideoFramePrompt(file: File) {
        val defaultName = "${file.nameWithoutExtension.ifBlank { file.name }}-cover.png"
        showTextInputDialog("导出封面帧", "输出文件名", defaultName) { input ->
            val target = uniqueDestination(activeTab().currentDir, if (input.endsWith(".png", true)) input else "$input.png")
            showLoading("FFmpeg 正在导出封面帧...")
            worker.execute {
                val result = MediaToolbox.extractVideoFrame(file, target)
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

    private fun showItemMenu(entry: FileEntry) {
        val file = entry.file ?: return
        val actions = mutableListOf<ActionSheetItem>()
        if (entry.isDirectory) {
            actions += ActionSheetItem("新标签打开", "在新标签页浏览这个文件夹", ActionTone.ACCENT) {
                if (tabs.size >= MAX_TABS) {
                    Toast.makeText(this, "最多同时打开 $MAX_TABS 个标签页", Toast.LENGTH_SHORT).show()
                } else {
                    val next = createTab(file)
                    activeTabId = next.id
                    clearSelection()
                    bindPanelScaffold()
                    renderDirectoryState(forceReload = true)
                }
            }
        } else {
            actions += ActionSheetItem("预览", "在悬浮窗里打开预览", ActionTone.ACCENT) {
                openPreview(file)
            }
        }
        actions += ActionSheetItem("重命名", "修改文件或目录名称") { renameFile(file) }
        actions += ActionSheetItem("复制", "加入复制剪贴板") {
            captureClipboard(move = false, files = listOf(file))
        }
        actions += ActionSheetItem("移动", "加入移动剪贴板") {
            captureClipboard(move = true, files = listOf(file))
        }
        actions += ActionSheetItem("多选", "将它加入当前选择集") {
            selectionMode = true
            selectedPaths.add(file.absolutePath)
            bindPanelScaffold()
            fileAdapter?.notifyDataSetChanged()
        }
        actions += ActionSheetItem("压缩为 ZIP", "生成一个新的压缩包") {
            compressFilesPrompt(listOf(file))
        }
        if (!entry.isDirectory && isArchiveFile(file)) {
            actions += ActionSheetItem("解压到当前目录", "在这里直接解压") {
                extractArchiveToCurrentDir(file)
            }
        }
        if (!entry.isDirectory && isImageFile(file)) {
            actions += ActionSheetItem("图片信息", "查看分辨率和格式") { showImageInfoDialog(file) }
            if (canTransformImage(file)) {
                actions += ActionSheetItem("旋转 90°", "输出一张旋转后的新图片") { rotateImagePrompt(file) }
                actions += ActionSheetItem("水平镜像", "输出一张镜像后的新图片") { mirrorImagePrompt(file) }
                actions += ActionSheetItem("导出 JPG", "压缩导出为 JPG") {
                    exportImagePrompt(file, ImageExportFormat.JPG)
                }
                actions += ActionSheetItem("导出 WEBP", "导出为 WEBP") {
                    exportImagePrompt(file, ImageExportFormat.WEBP)
                }
            }
        }
        if (!entry.isDirectory && isAudioFile(file)) {
            actions += ActionSheetItem("转为 MP3", "调用 FFmpeg 转换为 MP3") {
                convertAudioToMp3Prompt(file)
            }
            actions += ActionSheetItem("转为 M4A", "调用 FFmpeg 转换为 M4A") {
                convertAudioToM4aPrompt(file)
            }
            actions += ActionSheetItem("媒体信息", "查看音频元数据") { showMediaInfoDialog(file) }
        } else if (!entry.isDirectory && isVideoFile(file)) {
            actions += ActionSheetItem("提取音频", "从视频中提取音轨") {
                extractAudioFromVideoPrompt(file)
            }
            actions += ActionSheetItem("转为 MP4", "统一转码为 MP4 容器") {
                convertVideoToMp4Prompt(file)
            }
            actions += ActionSheetItem("导出封面帧", "从视频里抓取一张封面图") {
                extractVideoFramePrompt(file)
            }
            actions += ActionSheetItem("媒体信息", "查看视频元数据") { showMediaInfoDialog(file) }
        }
        actions += ActionSheetItem("删除", "删除此项目", ActionTone.DANGER) {
            selectedPaths.clear()
            selectedPaths.add(file.absolutePath)
            selectionMode = true
            deleteSelected()
        }
        showActionSheet(file.name, entry.meta, actions)
    }

    private fun showActionSheet(title: String, subtitle: String?, actions: List<ActionSheetItem>) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(12))
            background = rounded(PANEL_SURFACE_COLOR, 22, 1, PANEL_BORDER_COLOR)
        }
        root.addView(TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 2
        })
        subtitle?.takeIf { it.isNotBlank() }?.let { meta ->
            root.addView(TextView(this).apply {
                text = meta
                setTextColor(TEXT_SECONDARY_COLOR)
                textSize = 12f
                setPadding(0, dp(6), 0, 0)
                maxLines = 2
            })
        }

        val actionList = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.addView(
            ScrollView(this).apply {
                isVerticalScrollBarEnabled = false
                addView(actionList)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                min(dp(360), panelHeight() / 2),
            ).apply {
                topMargin = dp(12)
            },
        )

        val dialog = AlertDialog.Builder(this)
            .setView(root)
            .create()
        dialog.window?.setType(overlayType())
        dialog.window?.setBackgroundDrawable(GradientDrawable().apply { setColor(Color.TRANSPARENT) })

        actions.forEachIndexed { index, item ->
            actionList.addView(actionCard(item) {
                dialog.dismiss()
                item.action()
            })
            if (index != actions.lastIndex) {
                actionList.addView(View(this).apply {
                    setBackgroundColor(0x142C3647)
                }, LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(1),
                ).apply {
                    topMargin = dp(6)
                    bottomMargin = dp(6)
                })
            }
        }
        actionList.addView(tinyButton("关闭") { dialog.dismiss() }.apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(10)
            }
        })
        dialog.show()
    }

    private fun actionCard(item: ActionSheetItem, onClick: () -> Unit): View {
        val (surface, border, titleColor) = when (item.tone) {
            ActionTone.ACCENT -> Triple(0xFF13253A.toInt(), 0xFF3D6FA4.toInt(), 0xFFD7EBFF.toInt())
            ActionTone.DANGER -> Triple(0xFF31181A.toInt(), 0xFF8F3E46.toInt(), 0xFFFFD8DC.toInt())
            ActionTone.NEUTRAL -> Triple(0xFF171D26.toInt(), 0xFF2B3442.toInt(), Color.WHITE)
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(surface, 16, 1, border)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setOnClickListener { onClick() }
            addView(TextView(context).apply {
                text = item.title
                setTextColor(titleColor)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
            })
            item.subtitle?.takeIf { it.isNotBlank() }?.let { desc ->
                addView(TextView(context).apply {
                    text = desc
                    setTextColor(TEXT_MUTED_COLOR)
                    textSize = 11f
                    setPadding(0, dp(4), 0, 0)
                    maxLines = 2
                })
            }
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
        val cliToolsRoot = File(filesDir, "rootfs/ubuntu/opt/openclaw-cli")
        return buildList {
            add("内部" to sharedRoot)
            add("私有根" to privateRoot)
            add("files" to filesDir)
            if (cliToolsRoot.exists()) {
                add("CLI工具" to cliToolsRoot)
            }
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
        val cliToolsRoot = File(filesDir, "rootfs/ubuntu/opt/openclaw-cli")
        return when {
            path == defaultSharedRoot().absolutePath -> "内部存储"
            path == appPrivateRoot().absolutePath -> "应用私有"
            path == filesDir.absolutePath -> "files"
            path == cliToolsRoot.absolutePath -> "CLI工具"
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

    private fun isImageFile(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in imageExtensions
    }

    private fun canTransformImage(file: File): Boolean {
        return file.extension.lowercase(Locale.ROOT) in editableImageExtensions
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
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = rounded(
                if (selected) CHIP_ACTIVE_COLOR else CHIP_SURFACE_COLOR,
                16,
                1,
                if (selected) CHIP_ACTIVE_BORDER_COLOR else CHIP_BORDER_COLOR,
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

    private fun controlActionButton(
        icon: Int,
        label: String,
        selected: Boolean,
        expanded: Boolean,
        action: () -> Unit,
    ): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                if (expanded) dp(10) else dp(9),
                dp(8),
                if (expanded) dp(12) else dp(9),
                dp(8),
            )
            background = rounded(
                if (selected) 0xFF1E4774.toInt() else 0xFF18222D.toInt(),
                18,
                1,
                if (selected) 0xFF73B0FF.toInt() else 0xFF324456.toInt(),
            )
            isClickable = true
            isFocusable = true
            contentDescription = label
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(0, 0, dp(8), 0)
            }

            addView(
                ImageView(context).apply {
                    setImageResource(icon)
                    setColorFilter(if (selected) Color.WHITE else TEXT_SECONDARY_COLOR)
                    layoutParams = LinearLayout.LayoutParams(dp(18), dp(18))
                },
            )
            if (expanded) {
                addView(
                    TextView(context).apply {
                        text = label
                        setTextColor(Color.WHITE)
                        textSize = 12f
                        maxLines = 1
                        setPadding(dp(8), 0, 0, 0)
                    },
                )
            }
        }
    }

    private fun tinyButton(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = rounded(TOOLBAR_BUTTON_COLOR, 14, 1, TOOLBAR_BUTTON_BORDER_COLOR)
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMargins(dp(5), 0, 0, 0)
            }
        }
    }

    private fun toolbarBackIcon(): Int {
        return if (previewing) {
            R.drawable.lucide_chevron_left
        } else {
            R.drawable.lucide_upload
        }
    }

    private fun toolbarActionButton(icon: Int, description: String, action: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(icon)
            setColorFilter(0xFFE2EEFF.toInt())
            contentDescription = description
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            background = rounded(0xFF192330.toInt(), 16, 1, 0xFF35506B.toInt())
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply {
                setMargins(dp(6), 0, 0, 0)
            }
        }
    }

    private fun iconButton(icon: Int, action: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(icon)
            setColorFilter(Color.WHITE)
            background = rounded(TOOLBAR_BUTTON_COLOR, 14, 1, TOOLBAR_BUTTON_BORDER_COLOR)
            setPadding(dp(7), dp(7), dp(7), dp(7))
            setOnClickListener { action() }
        }
    }

    private fun createListHolder(parent: ViewGroup): FileViewHolder {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(9), dp(10), dp(9))
        }
        val icon = FrameLayout(this).apply {
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
        val icon = FrameLayout(this).apply {
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
        val baseSurface = when {
            selected -> 0xFF1E416C.toInt()
            entry.isDirectory || entry.isParent -> 0xFF1A2028.toInt()
            else -> 0xFF161A20.toInt()
        }
        val baseBorder = when {
            selected -> 0xFF79B1FF.toInt()
            entry.isDirectory || entry.isParent -> 0xFF485462.toInt()
            else -> 0xFF2B3440.toInt()
        }
        holder.itemView.background = rounded(
            baseSurface,
            if (grid) 14 else 12,
            1,
            baseBorder,
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
                    showItemMenu(entry)
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

    private fun bindIcon(icon: FrameLayout, file: File?, entry: FileEntry, grid: Boolean) {
        val size = if (grid) dp(50) else dp(38)
        icon.layoutParams.width = size
        icon.layoutParams.height = size
        icon.removeAllViews()
        icon.background = null
        if (file != null && !entry.isDirectory && file.extension.lowercase(Locale.ROOT) in imageExtensions) {
            val thumb = loadThumbnail(file, size)
            if (thumb != null) {
                renderThumbnailIcon(icon, thumb, imageBadgeLabel(file))
                return
            }
        }
        if (entry.isDirectory || entry.isParent) {
            renderFolderIcon(icon, if (entry.isParent) "UP" else "DIR")
        } else {
            renderFileIcon(icon, file, fileBadgeLabel(file))
        }
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

    private fun renderThumbnailIcon(container: FrameLayout, bitmap: Bitmap, badge: String) {
        container.addView(ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            setImageBitmap(bitmap)
            background = rounded(0xFF1C2531.toInt(), 14, 1, 0xFF3F536D.toInt())
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        container.addView(iconBadge(badge, 0xFF1C3C66.toInt()), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END,
        ).apply {
            rightMargin = dp(2)
            bottomMargin = dp(2)
        })
    }

    private fun renderFolderIcon(container: FrameLayout, label: String) {
        val iconRes = if (label == "UP") R.drawable.lucide_hard_drive else R.drawable.lucide_hard_drive
        renderSymbolCard(
            container = container,
            iconRes = iconRes,
            surfaceColor = 0x1FF9D17F,
            borderColor = 0xFFE0B14F.toInt(),
            iconTint = 0xFFF6C251.toInt(),
            badge = label,
            badgeColor = 0xFF5A3D10.toInt(),
        )
    }

    private fun renderFileIcon(container: FrameLayout, file: File?, badge: String) {
        val spec = resolveFileIconSpec(file)
        renderSymbolCard(
            container = container,
            iconRes = spec.resId,
            surfaceColor = spec.surfaceColor,
            borderColor = spec.borderColor,
            iconTint = spec.iconTint,
            badge = badge,
            badgeColor = spec.badgeColor,
        )
    }

    private fun renderSymbolCard(
        container: FrameLayout,
        iconRes: Int,
        surfaceColor: Int,
        borderColor: Int,
        iconTint: Int,
        badge: String,
        badgeColor: Int,
    ) {
        container.addView(View(this).apply {
            background = rounded(surfaceColor, 12, 1, borderColor)
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        container.addView(ImageView(this).apply {
            setImageResource(iconRes)
            setColorFilter(iconTint)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }, FrameLayout.LayoutParams(
            dp(24),
            dp(24),
            Gravity.CENTER,
        ))
        container.addView(iconBadge(badge, badgeColor), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END,
        ).apply {
            rightMargin = dp(2)
            bottomMargin = dp(2)
        })
    }

    private fun resolveFileIconSpec(file: File?): FileIconSpec {
        val ext = file?.extension?.lowercase(Locale.ROOT).orEmpty()
        return when {
            ext in textExtensions -> FileIconSpec(
                R.drawable.lucide_file_code,
                0xFF13202B.toInt(),
                0xFF345064.toInt(),
                0xFF6DB7FF.toInt(),
                0xFF1C3E61.toInt(),
            )
            ext in imageExtensions -> FileIconSpec(
                R.drawable.lucide_app_window,
                0xFF1A2115.toInt(),
                0xFF4A5D2B.toInt(),
                0xFFA8E16F.toInt(),
                0xFF35571C.toInt(),
            )
            ext in audioExtensions -> FileIconSpec(
                R.drawable.lucide_play,
                0xFF1F1627.toInt(),
                0xFF59406E.toInt(),
                0xFFE3A4FF.toInt(),
                0xFF5E2A76.toInt(),
            )
            ext in videoExtensions -> FileIconSpec(
                R.drawable.lucide_play,
                0xFF181B27.toInt(),
                0xFF394F7D.toInt(),
                0xFF97B7FF.toInt(),
                0xFF28406B.toInt(),
            )
            ext in archiveExtensions -> FileIconSpec(
                R.drawable.lucide_upload,
                0xFF231B14.toInt(),
                0xFF6F4D2F.toInt(),
                0xFFF0BF7A.toInt(),
                0xFF6B4318.toInt(),
            )
            else -> FileIconSpec(
                R.drawable.lucide_file_code,
                0xFF1A2029.toInt(),
                0xFF3B4A5C.toInt(),
                0xFFD7E6F9.toInt(),
                0xFF2A4761.toInt(),
            )
        }
    }

    private fun iconBadge(label: String, backgroundColor: Int): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 7f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(4), dp(2), dp(4), dp(2))
            background = rounded(backgroundColor, 8, 0, 0)
        }
    }

    private fun imageBadgeLabel(file: File): String {
        return when (file.extension.lowercase(Locale.ROOT)) {
            "png" -> "PNG"
            "jpg", "jpeg" -> "JPG"
            "webp" -> "WEBP"
            "gif" -> "GIF"
            else -> "IMG"
        }
    }

    private fun fileBadgeLabel(file: File?): String {
        val ext = file?.extension?.lowercase(Locale.ROOT).orEmpty()
        return when {
            ext in videoExtensions -> "VID"
            ext in audioExtensions -> "AUD"
            ext in textExtensions -> "TXT"
            ext in archiveExtensions -> "ZIP"
            ext == "pdf" -> "PDF"
            ext.isBlank() -> "FILE"
            else -> ext.take(4).uppercase(Locale.ROOT)
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
        var wrapEnabled: Boolean = false
            private set
        private var cursorStatusListener: (() -> Unit)? = null
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

        fun setCursorStatusListener(listener: () -> Unit) {
            cursorStatusListener = listener
        }

        override fun onSelectionChanged(selStart: Int, selEnd: Int) {
            super.onSelectionChanged(selStart, selEnd)
            cursorStatusListener?.invoke()
        }

        fun cursorLabel(): String {
            val content = text?.toString().orEmpty()
            val offset = selectionStart.coerceIn(0, content.length)
            val line = content.take(offset).count { it == '\n' } + 1
            val lineStart = if (offset == 0) {
                0
            } else {
                content.lastIndexOf('\n', offset - 1).let { if (it < 0) 0 else it + 1 }
            }
            val column = offset - lineStart + 1
            return "行 $line · 列 $column · ${content.length} 字符"
        }

        fun jumpToLine(lineNumber: Int): Boolean {
            if (lineNumber < 1) {
                return false
            }
            val content = text?.toString().orEmpty()
            var line = 1
            var index = 0
            while (line < lineNumber && index < content.length) {
                val next = content.indexOf('\n', index)
                if (next < 0) {
                    return false
                }
                index = next + 1
                line++
            }
            setSelection(index.coerceIn(0, length()))
            post {
                layout?.let { textLayout ->
                    val targetLine = textLayout.getLineForOffset(index.coerceIn(0, length()))
                    val top = textLayout.getLineTop(targetLine)
                    (parent as? ScrollView)?.smoothScrollTo(0, top)
                }
            }
            return true
        }

        fun findNext(query: String): Boolean {
            if (query.isBlank()) {
                return false
            }
            val source = text?.toString().orEmpty()
            if (source.isEmpty()) {
                return false
            }
            val start = selectionEnd.coerceAtLeast(0).coerceAtMost(source.length)
            var index = source.indexOf(query, start, ignoreCase = true)
            if (index < 0 && start > 0) {
                index = source.indexOf(query, 0, ignoreCase = true)
            }
            if (index < 0) {
                return false
            }
            requestFocus()
            setSelection(index, index + query.length)
            post {
                layout?.let { textLayout ->
                    val targetLine = textLayout.getLineForOffset(index)
                    val top = textLayout.getLineTop(targetLine)
                    (parent as? ScrollView)?.smoothScrollTo(0, top)
                }
            }
            return true
        }

        fun insertAtCursor(value: String) {
            val editable = text ?: return
            val start = selectionStart.coerceAtLeast(0)
            val end = selectionEnd.coerceAtLeast(0)
            editable.replace(min(start, end), max(start, end), value)
        }

        fun toggleWrap() {
            wrapEnabled = !wrapEnabled
            setHorizontallyScrolling(!wrapEnabled)
            isHorizontalScrollBarEnabled = !wrapEnabled
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
        val icon: FrameLayout,
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
        var scrollPosition: Int = 0,
        var scrollOffset: Int = 0,
    )

    private data class ClipboardState(
        val files: List<File>,
        val move: Boolean,
    )

    private data class ActionSheetItem(
        val title: String,
        val subtitle: String? = null,
        val tone: ActionTone = ActionTone.NEUTRAL,
        val action: () -> Unit,
    )

    private data class ImageInfo(
        val width: Int,
        val height: Int,
        val mimeType: String?,
    )

    private data class FileIconSpec(
        val resId: Int,
        val surfaceColor: Int,
        val borderColor: Int,
        val iconTint: Int,
        val badgeColor: Int,
    )

    private enum class ActionTone {
        NEUTRAL,
        ACCENT,
        DANGER,
    }

    private enum class ImageExportFormat(
        val extension: String,
        val label: String,
        val quality: Int,
    ) {
        JPG("jpg", "JPG", 92),
        PNG("png", "PNG", 100),
        WEBP("webp", "WEBP", 90);

        fun compressFormat(): Bitmap.CompressFormat {
            return when (this) {
                JPG -> Bitmap.CompressFormat.JPEG
                PNG -> Bitmap.CompressFormat.PNG
                WEBP -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Bitmap.CompressFormat.WEBP_LOSSY
                } else {
                    @Suppress("DEPRECATION")
                    Bitmap.CompressFormat.WEBP
                }
            }
        }

        companion object {
            fun fromFile(file: File): ImageExportFormat {
                return when (file.extension.lowercase(Locale.ROOT)) {
                    "jpg", "jpeg" -> JPG
                    "webp" -> WEBP
                    else -> PNG
                }
            }
        }
    }

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
        private val editableImageExtensions = setOf("jpg", "jpeg", "png", "webp", "bmp")
        private val videoExtensions = setOf("mp4", "mkv", "webm", "3gp", "mov", "avi")
        private val audioExtensions = setOf("mp3", "m4a", "aac", "wav", "ogg", "flac")
        private val archiveExtensions = setOf("zip", "apk", "jar")
        private val PANEL_SURFACE_COLOR = 0xFF0F141B.toInt()
        private val PANEL_BORDER_COLOR = 0xFF283241.toInt()
        private val CARD_SURFACE_COLOR = 0xFF141C26.toInt()
        private val CARD_BORDER_COLOR = 0xFF2A3647.toInt()
        private val CHIP_SURFACE_COLOR = 0xFF18202A.toInt()
        private val CHIP_BORDER_COLOR = 0xFF334253.toInt()
        private val CHIP_ACTIVE_COLOR = 0xFF1F4471.toInt()
        private val CHIP_ACTIVE_BORDER_COLOR = 0xFF6FA8EE.toInt()
        private val TOOLBAR_BUTTON_COLOR = 0xFF1A2430.toInt()
        private val TOOLBAR_BUTTON_BORDER_COLOR = 0xFF33465B.toInt()
        private val TEXT_SECONDARY_COLOR = 0xFF9EB1C8.toInt()
        private val TEXT_MUTED_COLOR = 0xFF7F8FA2.toInt()

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
