package com.openclaw.cyx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerControlView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class FloatingFileManagerService : Service() {
    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val directoryExecutor = Executors.newSingleThreadExecutor()
    private val loadGeneration = AtomicInteger(0)

    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var panelRoot: LinearLayout? = null

    private var currentDir: File = Environment.getExternalStorageDirectory()
    private var currentEntries: List<FileEntry> = emptyList()
    private var currentPreviewFile: File? = null
    private var currentPlayer: ExoPlayer? = null

    private var viewMode = ViewMode.LIST
    private var sortMode = SortMode.NAME
    private var showHidden = false
    private var previewing = false
    private var directoryLoading = false

    private var titleView: TextView? = null
    private var backButton: TextView? = null
    private var openButton: TextView? = null
    private var shareButton: TextView? = null
    private var minimizeButton: TextView? = null
    private var quickRootsScroll: HorizontalScrollView? = null
    private var quickRootsRow: LinearLayout? = null
    private var breadcrumbScroll: HorizontalScrollView? = null
    private var breadcrumbRow: LinearLayout? = null
    private var controlBarRow: LinearLayout? = null
    private var contentContainer: FrameLayout? = null
    private var statusView: TextView? = null
    private var recyclerView: RecyclerView? = null
    private var loadingView: TextView? = null
    private var fileAdapter: FileListAdapter? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForeground(NOTIFICATION_ID, buildNotification())
        showMinimizedBubble()
    }

    override fun onDestroy() {
        releasePlayer()
        loadGeneration.incrementAndGet()
        directoryExecutor.shutdownNow()
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
            .setContentText("Tap the floating button to browse shared storage.")
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
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 140
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

    private fun showMinimizedBubble() {
        releasePlayer()
        previewing = false
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
        previewing = false
        currentPreviewFile = null
        ensurePanelBuilt()
        panelRoot?.let { panel ->
            if (rootView !== panel) {
                replaceView(panel, panelWidth(), panelHeight())
            }
        }
        bindPanelScaffold()
        renderDirectoryState(forceReload = true)
    }

    private fun ensurePanelBuilt() {
        if (panelRoot != null) {
            return
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(8))
            background = rounded(0xF2131313.toInt(), 18, 1, 0xFF343434.toInt())
        }

        panel.addView(buildToolbar())
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

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(8))
        }
        controlBarRow = controls
        panel.addView(controls)

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

        val status = TextView(this).apply {
            setTextColor(0xFF8F8F8F.toInt())
            textSize = 10f
            maxLines = 2
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
        val open = tinyButton("打开") { currentPreviewFile?.let { openExternal(it) } }
        val share = tinyButton("分享") { currentPreviewFile?.let { shareFile(it) } }
        val minimize = tinyButton("最小") { showMinimizedBubble() }
        backButton = back
        openButton = open
        shareButton = share
        minimizeButton = minimize

        toolbar.addView(back)
        toolbar.addView(open)
        toolbar.addView(share)
        toolbar.addView(minimize)
        toolbar.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        return toolbar
    }

    private fun bindPanelScaffold() {
        titleView?.text = if (previewing) {
            currentPreviewFile?.name ?: "预览"
        } else {
            currentDir.name.ifBlank { "内部存储" }
        }

        backButton?.text = if (previewing) "返回" else "上级"
        openButton?.visibility = if (previewing) View.VISIBLE else View.GONE
        shareButton?.visibility = if (previewing) View.VISIBLE else View.GONE
        minimizeButton?.visibility = View.VISIBLE

        val browserVisibility = if (previewing) View.GONE else View.VISIBLE
        quickRootsScroll?.visibility = browserVisibility
        breadcrumbScroll?.visibility = browserVisibility
        controlBarRow?.visibility = browserVisibility

        if (!previewing) {
            rebuildQuickRoots()
            rebuildBreadcrumb()
            rebuildControlBar()
            updateLayoutManager()
        }
    }

    private fun rebuildQuickRoots() {
        val row = quickRootsRow ?: return
        row.removeAllViews()
        quickRootFiles().forEach { (label, file) ->
            if (file.exists()) {
                row.addView(chip(label, currentDir.absolutePath == file.absolutePath) {
                    currentDir = file
                    renderDirectoryState(forceReload = true)
                })
            }
        }
    }

    private fun rebuildBreadcrumb() {
        val row = breadcrumbRow ?: return
        row.removeAllViews()
        val storage = Environment.getExternalStorageDirectory()
        row.addView(chip("内部存储", currentDir.absolutePath == storage.absolutePath) {
            currentDir = storage
            renderDirectoryState(forceReload = true)
        })
        val relative = currentDir.relativeToOrNull(storage)
        var cursor = storage
        if (relative != null && relative.path != ".") {
            relative.path.split(File.separatorChar)
                .filter { it.isNotBlank() }
                .forEach { part ->
                    row.addView(TextView(this).apply {
                        text = "›"
                        setTextColor(0xFF777777.toInt())
                        textSize = 16f
                        setPadding(dp(4), 0, dp(4), 0)
                    })
                    cursor = File(cursor, part)
                    val target = cursor
                    row.addView(chip(part, currentDir.absolutePath == target.absolutePath) {
                        currentDir = target
                        renderDirectoryState(forceReload = true)
                    })
                }
        }
    }

    private fun rebuildControlBar() {
        val row = controlBarRow ?: return
        row.removeAllViews()
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

    private fun renderDirectoryState(forceReload: Boolean) {
        previewing = false
        currentPreviewFile = null
        bindPanelScaffold()
        if (forceReload) {
            loadDirectoryAsync()
        } else {
            fileAdapter?.submitList(currentEntries)
            showContent(if (currentEntries.isEmpty()) "没有文件，或当前目录无读取权限" else null)
            updateDirectoryStatus()
        }
    }

    private fun loadDirectoryAsync() {
        directoryLoading = true
        showContent("正在读取目录...")
        statusView?.text = currentDir.absolutePath
        val requestedDir = currentDir
        val generation = loadGeneration.incrementAndGet()
        directoryExecutor.execute {
            val files = visibleFiles(requestedDir)
            val entries = buildEntries(requestedDir, files)
            mainHandler.post {
                if (generation != loadGeneration.get()) {
                    return@post
                }
                if (previewing || currentDir.absolutePath != requestedDir.absolutePath) {
                    return@post
                }
                directoryLoading = false
                currentEntries = entries
                fileAdapter?.submitList(entries)
                showContent(if (entries.isEmpty()) "没有文件，或当前目录无读取权限" else null)
                updateDirectoryStatus()
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

    private fun updateDirectoryStatus() {
        val folderCount = currentEntries.count { !it.isParent && it.isDirectory }
        val fileCount = currentEntries.count { !it.isParent && !it.isDirectory }
        statusView?.text = "$folderCount 个文件夹 · $fileCount 个文件 · ${currentDir.absolutePath}"
    }

    private fun openPreview(file: File) {
        releasePlayer()
        previewing = true
        currentPreviewFile = file
        bindPanelScaffold()
        statusView?.text = "${formatSize(file.length())} · ${formatDate(file.lastModified())} · ${file.absolutePath}"

        val ext = file.extension.lowercase(Locale.ROOT)
        val previewView = when {
            ext in textExtensions -> textPreview(file)
            ext in imageExtensions -> imagePreview(file)
            ext in videoExtensions -> mediaPreview(file, isVideo = true)
            ext in audioExtensions -> mediaPreview(file, isVideo = false)
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
    }

    private fun closePreview() {
        releasePlayer()
        previewing = false
        currentPreviewFile = null
        bindPanelScaffold()
        renderDirectoryState(forceReload = false)
    }

    private fun textPreview(file: File): View {
        val text = try {
            file.inputStream().bufferedReader().use { it.readText().take(300_000) }
        } catch (e: Exception) {
            "读取失败: ${e.message}"
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

    private fun imagePreview(file: File): View {
        return FrameLayout(this).apply {
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
        }
    }

    private fun mediaPreview(file: File, isVideo: Boolean): View {
        val player = ExoPlayer.Builder(this).build()
        currentPlayer = player

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
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

        if (isVideo) {
            val textureView = TextureView(this)
            mediaSurface.addView(
                textureView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
            player.setVideoTextureView(textureView)
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

        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Toast.makeText(
                    this@FloatingFileManagerService,
                    "悬浮窗无法播放此文件，请用外部应用打开",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        })
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
        player.prepare()
        player.playWhenReady = true
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
        val parent = currentDir.parentFile
        if (parent != null && parent.canRead()) {
            currentDir = parent
            renderDirectoryState(forceReload = true)
        } else {
            showMinimizedBubble()
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
            SortMode.TYPE -> compareBy<File>({ if (it.isDirectory) 0 else 1 }, { it.extension.lowercase(Locale.ROOT) }, { it.name.lowercase(Locale.ROOT) })
        }
        return files.sortedWith(comparator)
    }

    private fun fileMeta(file: File): String {
        return if (file.isDirectory) {
            "文件夹 · ${formatDate(file.lastModified())}"
        } else {
            "${formatSize(file.length())} · ${formatDate(file.lastModified())}"
        }
    }

    private fun quickRootFiles(): List<Pair<String, File>> {
        val root = Environment.getExternalStorageDirectory()
        return listOf(
            "内部" to root,
            "下载" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "图片" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "DCIM" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
            "文档" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
            "视频" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "音乐" to Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
        )
    }

    private fun mimeFor(file: File): String {
        val ext = file.extension.lowercase(Locale.ROOT)
        return when {
            ext in textExtensions -> "text/plain"
            ext in imageExtensions -> "image/*"
            ext in videoExtensions -> "video/*"
            ext in audioExtensions -> "audio/*"
            ext == "pdf" -> "application/pdf"
            else -> "*/*"
        }
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

    private fun typeIcon(directory: Boolean, name: String): TextView {
        val ext = File(name).extension.lowercase(Locale.ROOT)
        val label = when {
            directory -> "DIR"
            ext in imageExtensions -> "IMG"
            ext in videoExtensions -> "VID"
            ext in audioExtensions -> "AUD"
            ext in textExtensions -> "TXT"
            ext == "pdf" -> "PDF"
            else -> "FILE"
        }
        val color = when {
            directory -> 0xFF315A9C.toInt()
            ext in imageExtensions -> 0xFF2C7A55.toInt()
            ext in videoExtensions -> 0xFF7C3B82.toInt()
            ext in audioExtensions -> 0xFF8A5B2E.toInt()
            ext in textExtensions -> 0xFF3D6477.toInt()
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
            background = rounded(0xFF202020.toInt(), 12, 1, 0xFF2F2F2F.toInt())
        }
        val icon = typeIcon(false, "file").apply {
            layoutParams = LinearLayout.LayoutParams(dp(34), dp(34))
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
            maxLines = 1
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
            background = rounded(0xFF202020.toInt(), 14, 1, 0xFF303030.toInt())
        }
        val icon = typeIcon(false, "file").apply {
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(42))
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
        val replacementIcon = typeIcon(entry.isDirectory, entry.title)
        holder.icon.text = replacementIcon.text
        holder.icon.setTextColor(replacementIcon.currentTextColor)
        holder.icon.textSize = replacementIcon.textSize / resources.displayMetrics.scaledDensity
        holder.icon.typeface = Typeface.DEFAULT_BOLD
        holder.icon.background = replacementIcon.background
        holder.title.text = entry.title
        holder.meta.text = entry.meta
        holder.itemView.setOnClickListener {
            if (entry.isParent) {
                currentDir = entry.file ?: currentDir
                renderDirectoryState(forceReload = true)
            } else if (entry.isDirectory) {
                currentDir = entry.file ?: currentDir
                renderDirectoryState(forceReload = true)
            } else {
                entry.file?.let { openPreview(it) }
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
