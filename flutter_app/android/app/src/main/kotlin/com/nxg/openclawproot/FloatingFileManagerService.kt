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
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.MediaController
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import android.widget.VideoView
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class FloatingFileManagerService : Service() {
    private lateinit var windowManager: WindowManager
    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var currentDir: File = Environment.getExternalStorageDirectory()
    private var viewMode = ViewMode.LIST
    private var sortMode = SortMode.NAME
    private var showHidden = false
    private var previewing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForeground(NOTIFICATION_ID, buildNotification())
        showMinimizedBubble()
    }

    override fun onDestroy() {
        rootView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
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
        previewing = false
        val panel = basePanel()
        panel.addView(toolbar(currentDir.name.ifBlank { "内部存储" }))
        panel.addView(quickRoots())
        panel.addView(breadcrumb())
        panel.addView(controlBar())

        val files = visibleFiles(currentDir)
        val listContent = if (files.isEmpty()) {
            emptyRow("没有文件，或当前目录无读取权限")
        } else if (viewMode == ViewMode.GRID) {
            gridContent(files)
        } else {
            listContent(files)
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = false
            addView(listContent)
        }
        panel.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        panel.addView(statusBar(files))
        replaceView(panel, panelWidth(), panelHeight())
    }

    private fun basePanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(10), dp(10), dp(8))
            background = rounded(0xF2131313.toInt(), 18, 1, 0xFF343434.toInt())
        }
    }

    private fun toolbar(titleText: String): LinearLayout {
        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(2), dp(2), dp(8))
        }
        attachDrag(toolbar)

        toolbar.addView(TextView(this).apply {
            text = titleText
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        toolbar.addView(tinyButton("上级") { goParent() })
        toolbar.addView(tinyButton("最小") { showMinimizedBubble() })
        toolbar.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        return toolbar
    }

    private fun quickRoots(): HorizontalScrollView {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 0, 0, dp(8))
        }
        quickRootFiles().forEach { (label, file) ->
            if (file.exists()) {
                row.addView(chip(label, currentDir.absolutePath == file.absolutePath) {
                    currentDir = file
                    showFilePanel()
                })
            }
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun breadcrumb(): HorizontalScrollView {
        val storage = Environment.getExternalStorageDirectory()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(8))
        }
        row.addView(chip("内部存储", currentDir.absolutePath == storage.absolutePath) {
            currentDir = storage
            showFilePanel()
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
                        showFilePanel()
                    })
                }
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun controlBar(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(8))
            addView(chip(if (viewMode == ViewMode.LIST) "列表" else "网格", true) {
                viewMode = if (viewMode == ViewMode.LIST) ViewMode.GRID else ViewMode.LIST
                showFilePanel()
            })
            addView(chip(sortMode.label, false) {
                sortMode = sortMode.next()
                showFilePanel()
            })
            addView(chip(if (showHidden) "隐藏:开" else "隐藏:关", showHidden) {
                showHidden = !showHidden
                showFilePanel()
            })
            addView(chip("刷新", false) { showFilePanel() })
        }
    }

    private fun listContent(files: List<File>): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            currentDir.parentFile?.let { parent ->
                addView(fileRow("..", "返回上级目录", true) {
                    currentDir = parent
                    showFilePanel()
                })
            }
            files.forEach { file ->
                addView(fileRow(file.name, fileMeta(file), file.isDirectory) {
                    if (file.isDirectory) {
                        currentDir = file
                        showFilePanel()
                    } else {
                        openPreview(file)
                    }
                })
            }
        }
    }

    private fun gridContent(files: List<File>): LinearLayout {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        val cells = mutableListOf<View>()
        currentDir.parentFile?.let { parent ->
            cells.add(gridCell("..", "上级", true) {
                currentDir = parent
                showFilePanel()
            })
        }
        files.forEach { file ->
            cells.add(gridCell(file.name, fileMeta(file), file.isDirectory) {
                if (file.isDirectory) {
                    currentDir = file
                    showFilePanel()
                } else {
                    openPreview(file)
                }
            })
        }
        cells.chunked(2).forEach { pair ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            pair.forEach { cell ->
                row.addView(cell, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    setMargins(dp(3), dp(3), dp(3), dp(3))
                })
            }
            if (pair.size == 1) {
                row.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
            }
            container.addView(row)
        }
        return container
    }

    private fun fileRow(name: String, meta: String, directory: Boolean, onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
            background = rounded(0xFF202020.toInt(), 12, 1, 0xFF2F2F2F.toInt())
            setOnClickListener { onClick() }

            addView(typeIcon(directory, name), LinearLayout.LayoutParams(dp(34), dp(34)))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(10), 0, 0, 0)
                addView(TextView(context).apply {
                    text = name
                    setTextColor(Color.WHITE)
                    textSize = 14f
                    maxLines = 1
                })
                addView(TextView(context).apply {
                    text = meta
                    setTextColor(0xFFAAAAAA.toInt())
                    textSize = 11f
                    maxLines = 1
                })
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }.apply {
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            lp.setMargins(0, 0, 0, dp(6))
            layoutParams = lp
        }
    }

    private fun gridCell(name: String, meta: String, directory: Boolean, onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), dp(10), dp(8), dp(8))
            background = rounded(0xFF202020.toInt(), 14, 1, 0xFF303030.toInt())
            setOnClickListener { onClick() }
            addView(typeIcon(directory, name), LinearLayout.LayoutParams(dp(42), dp(42)))
            addView(TextView(context).apply {
                text = name
                setTextColor(Color.WHITE)
                textSize = 12f
                maxLines = 2
                gravity = Gravity.CENTER
            })
            addView(TextView(context).apply {
                text = meta
                setTextColor(0xFF9A9A9A.toInt())
                textSize = 10f
                maxLines = 1
                gravity = Gravity.CENTER
            })
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

    private fun emptyRow(message: String): View {
        return FrameLayout(this).apply {
            setPadding(dp(8), dp(28), dp(8), dp(28))
            addView(TextView(context).apply {
                text = message
                setTextColor(0xFFB8B8B8.toInt())
                gravity = Gravity.CENTER
                textSize = 13f
            }, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ))
        }
    }

    private fun statusBar(files: List<File>): TextView {
        val folderCount = files.count { it.isDirectory }
        val fileCount = files.size - folderCount
        return TextView(this).apply {
            text = "$folderCount 个文件夹 · $fileCount 个文件 · ${currentDir.absolutePath}"
            setTextColor(0xFF8F8F8F.toInt())
            textSize = 10f
            maxLines = 1
            setPadding(dp(4), dp(6), dp(4), 0)
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

    private fun openPreview(file: File) {
        previewing = true
        val panel = basePanel()
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(2), dp(2), dp(8))
        }
        attachDrag(header)
        header.addView(TextView(this).apply {
            text = file.name
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(tinyButton("返回") { showFilePanel() })
        header.addView(tinyButton("打开") { openExternal(file) })
        header.addView(tinyButton("分享") { shareFile(file) })
        header.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        panel.addView(header)

        panel.addView(TextView(this).apply {
            text = "${formatSize(file.length())} · ${formatDate(file.lastModified())} · ${file.absolutePath}"
            setTextColor(0xFFA8A8A8.toInt())
            textSize = 11f
            maxLines = 2
            setPadding(dp(2), 0, dp(2), dp(8))
        })

        val ext = file.extension.lowercase(Locale.ROOT)
        val content = when {
            ext in textExtensions -> textPreview(file)
            ext in imageExtensions -> imagePreview(file)
            ext in videoExtensions || ext in audioExtensions -> mediaPreview(file)
            else -> emptyRow("此格式不支持悬浮预览，可点击“打开”调用外部应用。")
        }
        panel.addView(content, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        replaceView(panel, panelWidth(), panelHeight())
    }

    private fun textPreview(file: File): View {
        val text = try {
            file.inputStream().bufferedReader().use { it.readText().take(300_000) }
        } catch (e: Exception) {
            "读取失败: ${e.message}"
        }
        return ScrollView(this).apply {
            background = rounded(Color.BLACK, 12, 1, 0xFF303030.toInt())
            addView(TextView(context).apply {
                this.text = text
                setTextColor(Color.WHITE)
                textSize = 12f
                typeface = Typeface.MONOSPACE
                setPadding(dp(10), dp(10), dp(10), dp(10))
            })
        }
    }

    private fun imagePreview(file: File): View {
        return ImageView(this).apply {
            background = rounded(Color.BLACK, 12, 1, 0xFF303030.toInt())
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
            setImageURI(Uri.fromFile(file))
        }
    }

    private fun mediaPreview(file: File): View {
        return VideoView(this).apply {
            background = rounded(Color.BLACK, 12, 1, 0xFF303030.toInt())
            setVideoURI(Uri.fromFile(file))
            setMediaController(MediaController(context).also { it.setAnchorView(this) })
            setOnPreparedListener { start() }
            setOnErrorListener { _, _, _ ->
                Toast.makeText(context, "悬浮窗无法播放此文件，请用外部应用打开", Toast.LENGTH_SHORT).show()
                true
            }
        }
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
        } catch (e: Exception) {
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
        } catch (e: Exception) {
            Toast.makeText(this, "无法分享此文件", Toast.LENGTH_SHORT).show()
        }
    }

    private fun goParent() {
        if (previewing) {
            showFilePanel()
            return
        }
        val parent = currentDir.parentFile
        if (parent != null && parent.canRead()) {
            currentDir = parent
            showFilePanel()
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
            SortMode.NAME -> compareBy<File> { if (it.isDirectory) 0 else 1 }
                .thenBy { it.name.lowercase(Locale.ROOT) }
            SortMode.DATE -> compareByDescending<File> { it.lastModified() }
                .thenBy { it.name.lowercase(Locale.ROOT) }
            SortMode.SIZE -> compareBy<File> { if (it.isDirectory) 0 else 1 }
                .thenByDescending { if (it.isDirectory) 0L else it.length() }
            SortMode.TYPE -> compareBy<File> { if (it.isDirectory) "0" else it.extension.lowercase(Locale.ROOT) }
                .thenBy { it.name.lowercase(Locale.ROOT) }
        }
        return files.sortedWith(comparator)
    }

    private fun fileMeta(file: File): String {
        return if (file.isDirectory) {
            val count = file.listFiles()?.size
            if (count == null) "文件夹 · 无权限" else "文件夹 · $count 项"
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

    private fun panelWidth(): Int {
        val width = resources.displayMetrics.widthPixels
        return min(max(dp(350), width - dp(28)), dp(520))
    }

    private fun panelHeight(): Int {
        val height = resources.displayMetrics.heightPixels
        return min(max(dp(500), (height * 0.72f).toInt()), height - dp(80))
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
            val values = SortMode.values()
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
