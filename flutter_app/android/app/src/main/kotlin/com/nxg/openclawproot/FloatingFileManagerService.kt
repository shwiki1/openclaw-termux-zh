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
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
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

class FloatingFileManagerService : Service() {
    private lateinit var windowManager: WindowManager
    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var currentDir: File = Environment.getExternalStorageDirectory()
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
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 180
        }
    }

    private fun replaceView(view: View, width: Int, height: Int) {
        rootView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        val nextParams = baseParams(width, height)
        params = nextParams
        rootView = view
        windowManager.addView(view, nextParams)
    }

    private fun showMinimizedBubble() {
        val bubble = TextView(this).apply {
            text = "Files"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(18, 12, 18, 12)
            setBackgroundColor(Color.rgb(26, 26, 26))
            setOnClickListener { showFilePanel() }
        }
        attachDrag(bubble)
        replaceView(bubble, WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT)
    }

    private fun showFilePanel() {
        previewing = false
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(18, 18, 18))
            setPadding(10, 10, 10, 10)
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        attachDrag(header)

        val title = TextView(this).apply {
            text = currentDir.absolutePath
            setTextColor(Color.WHITE)
            textSize = 13f
            maxLines = 2
        }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(iconButton(android.R.drawable.ic_menu_revert) { goBackOrMinimize() })
        header.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        panel.addView(header)

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        buildDirectoryRows(list)
        val scroll = ScrollView(this).apply {
            addView(list)
        }
        panel.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        replaceView(panel, dp(330), dp(480))
    }

    private fun buildDirectoryRows(list: LinearLayout) {
        val files = currentDir.listFiles()
            ?.filter { !it.isHidden || it.name.startsWith(".") }
            ?.sortedWith(compareBy<File> { if (it.isDirectory) 0 else 1 }.thenBy { it.name.lowercase(Locale.ROOT) })
            ?: emptyList()
        if (currentDir.parentFile != null) {
            list.addView(fileRow("..", "Parent directory") {
                currentDir.parentFile?.let {
                    currentDir = it
                    showFilePanel()
                }
            })
        }
        if (files.isEmpty()) {
            list.addView(emptyRow("Empty or no permission"))
        }
        for (file in files) {
            val meta = if (file.isDirectory) {
                "Folder"
            } else {
                "${formatSize(file.length())}  ${formatDate(file.lastModified())}"
            }
            list.addView(fileRow(file.name, meta) {
                if (file.isDirectory) {
                    currentDir = file
                    showFilePanel()
                } else {
                    openPreview(file)
                }
            })
        }
    }

    private fun fileRow(name: String, meta: String, onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(8, 10, 8, 10)
            setBackgroundColor(Color.rgb(24, 24, 24))
            setOnClickListener { onClick() }
            addView(TextView(context).apply {
                text = name
                setTextColor(Color.WHITE)
                textSize = 14f
                maxLines = 1
            })
            addView(TextView(context).apply {
                text = meta
                setTextColor(Color.rgb(170, 170, 170))
                textSize = 11f
                maxLines = 1
            })
        }
    }

    private fun emptyRow(message: String): View {
        return TextView(this).apply {
            text = message
            setTextColor(Color.rgb(180, 180, 180))
            gravity = Gravity.CENTER
            setPadding(12, 36, 12, 36)
        }
    }

    private fun iconButton(icon: Int, action: () -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(icon)
            setColorFilter(Color.WHITE)
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { action() }
        }
    }

    private fun openPreview(file: File) {
        previewing = true
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(14, 14, 14))
            setPadding(10, 10, 10, 10)
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        attachDrag(header)
        header.addView(TextView(this).apply {
            text = file.name
            setTextColor(Color.WHITE)
            textSize = 13f
            maxLines = 1
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(iconButton(android.R.drawable.ic_media_previous) { showFilePanel() })
        header.addView(iconButton(android.R.drawable.ic_menu_share) { openExternal(file) })
        header.addView(iconButton(android.R.drawable.ic_menu_close_clear_cancel) { stopSelf() })
        panel.addView(header)

        val ext = file.extension.lowercase(Locale.ROOT)
        val content = when {
            ext in textExtensions -> textPreview(file)
            ext in imageExtensions -> imagePreview(file)
            ext in videoExtensions || ext in audioExtensions -> mediaPreview(file)
            else -> emptyRow("Preview not supported. Tap share to open with another app.")
        }
        panel.addView(content, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        replaceView(panel, dp(340), dp(500))
    }

    private fun textPreview(file: File): View {
        val text = try {
            file.inputStream().bufferedReader().use { it.readText().take(300_000) }
        } catch (e: Exception) {
            "Failed to read file: ${e.message}"
        }
        return ScrollView(this).apply {
            addView(TextView(context).apply {
                this.text = text
                setTextColor(Color.WHITE)
                textSize = 12f
                typeface = Typeface.MONOSPACE
                setPadding(8, 8, 8, 8)
            })
        }
    }

    private fun imagePreview(file: File): View {
        return ImageView(this).apply {
            setBackgroundColor(Color.BLACK)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageURI(Uri.fromFile(file))
        }
    }

    private fun mediaPreview(file: File): View {
        return VideoView(this).apply {
            setVideoURI(Uri.fromFile(file))
            setMediaController(MediaController(context).also { it.setAnchorView(this) })
            setOnPreparedListener { start() }
            setOnErrorListener { _, _, _ ->
                Toast.makeText(context, "Cannot play this file in floating window", Toast.LENGTH_SHORT).show()
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
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(this, "No app can open this file", Toast.LENGTH_SHORT).show()
        }
    }

    private fun goBackOrMinimize() {
        if (previewing) {
            showFilePanel()
            return
        }
        showMinimizedBubble()
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
                    val moved = kotlin.math.abs(event.rawX - downX) + kotlin.math.abs(event.rawY - downY)
                    if (moved < 12f) {
                        view.performClick()
                    }
                    true
                }
                else -> true
            }
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
            else -> "*/*"
        }
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

    companion object {
        private const val NOTIFICATION_ID = 7071
        @Volatile
        var running: Boolean = false
            private set
        private val textExtensions = setOf(
            "txt", "md", "json", "xml", "html", "htm", "css", "js", "ts",
            "dart", "kt", "java", "py", "sh", "log", "yaml", "yml", "toml",
            "ini", "conf", "csv",
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
