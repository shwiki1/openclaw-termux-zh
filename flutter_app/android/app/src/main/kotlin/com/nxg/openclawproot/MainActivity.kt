package com.agent.cyx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.app.Activity
import android.content.Context
import android.os.Environment
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.OpenableColumns
import android.view.WindowManager
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.agent.cyx/native"
    private val SETUP_LOG_EVENT_CHANNEL = "com.agent.cyx/setup_logs"

    private lateinit var bootstrapManager: BootstrapManager
    private lateinit var processManager: ProcessManager
    private var setupLogSink: EventChannel.EventSink? = null
    private var snapshotSaveResult: MethodChannel.Result? = null
    private var pendingSnapshotContent: String? = null
    private var pendingSnapshotName: String? = null
    private var bootstrapArchivePickResult: MethodChannel.Result? = null
    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private var pendingNativeTerminalResult: MethodChannel.Result? = null
    private var setupDone = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "openclaw/native_terminal",
                NativeTerminalViewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                    applicationContext,
                ),
            )

        val filesDir = applicationContext.filesDir.absolutePath
        val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir

        bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)
        processManager = ProcessManager(filesDir, nativeLibDir)
        processManager.installLogEmitter = { line ->
            runOnUiThread {
                setupLogSink?.success(line)
            }
        }

        // Ensure directories and resolv.conf exist on every app start.
        // Android may clear filesDir during APK update (#40).
        if (!setupDone) {
            setupDone = true
            Thread {
                try { bootstrapManager.setupDirectories() } catch (_: Exception) {}
                try { bootstrapManager.writeResolvConf() } catch (_: Exception) {}
            }.start()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getProotPath" -> {
                    result.success(processManager.getProotPath())
                }
                "getArch" -> {
                    result.success(ArchUtils.getArch())
                }
                "getFilesDir" -> {
                    result.success(filesDir)
                }
                "getNativeLibDir" -> {
                    result.success(nativeLibDir)
                }
                "getWebViewPackageInfo" -> {
                    result.success(getWebViewPackageInfo())
                }
                "getAppPackageInfo" -> {
                    result.success(getAppPackageInfo())
                }
                "isBootstrapComplete" -> {
                    result.success(bootstrapManager.isBootstrapComplete())
                }
                "getBootstrapStatus" -> {
                    result.success(bootstrapManager.getBootstrapStatus())
                }
                "extractRootfs" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractRootfs(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "runInProot" -> {
                    val command = call.argument<String>("command")
                    val timeout = call.argument<Int>("timeout")?.toLong() ?: 900L
                    val keepForeground = call.argument<Boolean>("keepForeground") ?: false
                    val foregroundText = call.argument<String>("foregroundText") ?: "Running CLI task..."
                    if (command != null) {
                        Thread {
                            try {
                                if (keepForeground) {
                                    SetupService.retain(applicationContext, foregroundText, -1)
                                }
                                bootstrapManager.setupDirectories()
                                bootstrapManager.writeResolvConf()
                                val output = processManager.runInProotSync(command, timeout)
                                runOnUiThread { result.success(output) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PROOT_ERROR", e.message, null) }
                            } finally {
                                if (keepForeground) {
                                    SetupService.stop(applicationContext)
                                }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "command required", null)
                    }
                }
                "startLocalApiProxy" -> {
                    try {
                        LocalApiProxyForegroundService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopLocalApiProxy" -> {
                    try {
                        LocalApiProxyForegroundService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isLocalApiProxyRunning" -> {
                    result.success(LocalApiProxyForegroundService.isRunning)
                }
                "startTerminalService" -> {
                    try {
                        TerminalSessionService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "openNativeTerminalActivity" -> {
                    if (pendingNativeTerminalResult != null) {
                        result.error(
                            "TERMINAL_ACTIVITY_BUSY",
                            "A native terminal activity is already open.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        val executable = call.argument<String>("executable")
                        if (executable.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "executable required", null)
                            return@setMethodCallHandler
                        }
                        val config = NativeTerminalSessionConfig(
                            sessionId = call.argument<String>("sessionId") ?: "native-shell",
                            title = call.argument<String>("title") ?: "Terminal",
                            executable = executable,
                            cwd = call.argument<String>("cwd") ?: "/",
                            arguments = call.argument<List<String>>("arguments") ?: emptyList(),
                            environment = call.argument<Map<String, String>>("environment") ?: emptyMap(),
                            restart = call.argument<Boolean>("restart") ?: false,
                            keepAlive = call.argument<Boolean>("keepAlive") ?: true,
                            emitOutput = call.argument<Boolean>("emitOutput") ?: false,
                            renderingPaused = call.argument<Boolean>("renderingPaused") ?: false,
                            useNativeToolbar = call.argument<Boolean>("useNativeToolbar") ?: true,
                            transcriptRows = call.argument<Int>("transcriptRows") ?: 3000,
                            fontSize = call.argument<Int>("fontSize") ?: 18,
                        )
                        pendingNativeTerminalResult = result
                        startActivityForResult(
                            NativeTerminalActivity.createIntent(this, config),
                            NATIVE_TERMINAL_ACTIVITY_REQUEST,
                        )
                    } catch (e: Exception) {
                        pendingNativeTerminalResult = null
                        result.error("TERMINAL_ACTIVITY_ERROR", e.message, null)
                    }
                }
                "openNativeTerminalPagerActivity" -> {
                    if (pendingNativeTerminalResult != null) {
                        result.error(
                            "TERMINAL_ACTIVITY_BUSY",
                            "A native terminal activity is already open.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        val executable = call.argument<String>("executable")
                        if (executable.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "executable required", null)
                            return@setMethodCallHandler
                        }
                        val config = NativeTerminalSessionConfig(
                            sessionId = call.argument<String>("sessionId") ?: "native-shell",
                            title = call.argument<String>("title") ?: "Terminal",
                            executable = executable,
                            cwd = call.argument<String>("cwd") ?: "/",
                            arguments = call.argument<List<String>>("arguments") ?: emptyList(),
                            environment = call.argument<Map<String, String>>("environment") ?: emptyMap(),
                            restart = call.argument<Boolean>("restart") ?: false,
                            keepAlive = call.argument<Boolean>("keepAlive") ?: true,
                            emitOutput = call.argument<Boolean>("emitOutput") ?: false,
                            renderingPaused = call.argument<Boolean>("renderingPaused") ?: false,
                            useNativeToolbar = call.argument<Boolean>("useNativeToolbar") ?: true,
                            transcriptRows = call.argument<Int>("transcriptRows") ?: 3000,
                            fontSize = call.argument<Int>("fontSize") ?: 18,
                        )
                        pendingNativeTerminalResult = result
                        startActivityForResult(
                            NativeTerminalPagerActivity.createIntent(this, config),
                            NATIVE_TERMINAL_PAGER_ACTIVITY_REQUEST,
                        )
                    } catch (e: Exception) {
                        pendingNativeTerminalResult = null
                        result.error("TERMINAL_ACTIVITY_ERROR", e.message, null)
                    }
                }
                "invokeNativeBrowserAction" -> {
                    val action = call.argument<String>("action")?.trim().orEmpty()
                    if (action.isEmpty()) {
                        result.error("INVALID_ARGS", "action required", null)
                        return@setMethodCallHandler
                    }
                    val payload = (call.argument<Map<*, *>>("payload") ?: emptyMap<Any?, Any?>())
                        .mapNotNull { (key, value) ->
                            val stringKey = key as? String ?: return@mapNotNull null
                            stringKey to value
                        }
                        .toMap()
                    val controller = NativeBrowserAutomationRegistry.controller
                    if (controller == null) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "message" to "Native browser is not attached.",
                            ),
                        )
                        return@setMethodCallHandler
                    }
                    controller.executeAction(action, payload) { actionResult ->
                        runOnUiThread {
                            result.success(actionResult)
                        }
                    }
                }
                "stopTerminalService" -> {
                    try {
                        TerminalSessionService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isTerminalServiceRunning" -> {
                    result.success(TerminalSessionService.isRunning)
                }
                "setRootPassword" -> {
                    val password = call.argument<String>("password")
                    if (password != null) {
                        Thread {
                            try {
                                val escaped = password.replace("'", "'\\''")
                                processManager.runInProotSync(
                                    "echo 'root:$escaped' | chpasswd", 15
                                )
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SSH_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "password required", null)
                    }
                }
                "requestBatteryOptimization" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:${packageName}")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                "isBatteryOptimized" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(!pm.isIgnoringBatteryOptimizations(packageName))
                }
                "setupDirs" -> {
                    Thread {
                        try {
                            bootstrapManager.setupDirectories()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SETUP_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "installBionicBypass" -> {
                    Thread {
                        try {
                            bootstrapManager.installBionicBypass()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("BYPASS_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "writeResolv" -> {
                    Thread {
                        try {
                            bootstrapManager.writeResolvConf()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RESOLV_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "copyBundledAssetToFile" -> {
                    val assetPath = call.argument<String>("assetPath")
                    val destinationPath = call.argument<String>("destinationPath")
                    if (!assetPath.isNullOrBlank() && !destinationPath.isNullOrBlank()) {
                        Thread {
                            try {
                                bootstrapManager.copyBundledAssetToFile(assetPath, destinationPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("ASSET_COPY_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    } else {
                        result.error(
                            "INVALID_ARGS",
                            "assetPath and destinationPath required",
                            null
                        )
                    }
                }
                "extractDebPackages" -> {
                    Thread {
                        try {
                            val count = bootstrapManager.extractDebPackages()
                            runOnUiThread { result.success(count) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DEB_EXTRACT_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "extractNodeTarball" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractNodeTarball(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NODE_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "createBinWrappers" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        Thread {
                            try {
                                bootstrapManager.createBinWrappers(packageName)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("BIN_WRAPPER_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "packageName required", null)
                    }
                }
                "startSetupService" -> {
                    try {
                        SetupService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "updateSetupNotification" -> {
                    val text = call.argument<String>("text")
                    val progress = call.argument<Int>("progress") ?: -1
                    if (text != null) {
                        SetupService.updateNotification(text, progress)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "text required", null)
                    }
                }
                "stopSetupService" -> {
                    try {
                        SetupService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "showUrlNotification" -> {
                    val url = call.argument<String>("url")
                    val title = call.argument<String>("title") ?: "URL Detected"
                    if (url != null) {
                        showUrlNotification(url, title)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "url required", null)
                    }
                }
                "saveSnapshotFile" -> {
                    val suggestedName = call.argument<String>("suggestedName")
                    val content = call.argument<String>("content")
                    if (suggestedName.isNullOrBlank() || content == null) {
                        result.error(
                            "INVALID_ARGS",
                            "suggestedName and content required",
                            null
                        )
                    } else {
                        snapshotSaveResult = result
                        pendingSnapshotContent = content
                        pendingSnapshotName = suggestedName
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, suggestedName)
                        }
                        startActivityForResult(intent, SNAPSHOT_SAVE_REQUEST)
                    }
                }
                "pickBootstrapArchiveFile" -> {
                    bootstrapArchivePickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf(
                                "application/gzip",
                                "application/x-gzip",
                                "application/x-gtar",
                                "application/x-tar",
                                "application/x-xz",
                                "application/octet-stream"
                            )
                        )
                    }
                    startActivityForResult(intent, BOOTSTRAP_ARCHIVE_PICK_REQUEST)
                }
                "copyToClipboard" -> {
                    val text = call.argument<String>("text")
                    if (text != null) {
                        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("URL", text))
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "text required", null)
                    }
                }
                "vibrate" -> {
                    val durationMs = call.argument<Int>("durationMs")?.toLong() ?: 200L
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val vibratorManager =
                                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                            val vibrator = vibratorManager.defaultVibrator
                            vibrator.vibrate(
                                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(
                                    VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(durationMs)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIBRATE_ERROR", e.message, null)
                    }
                }
                "requestStoragePermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            if (Environment.isExternalStorageManager()) {
                                result.success(true)
                                return@setMethodCallHandler
                            }

                            pendingStoragePermissionResult = result
                            val appIntent = Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            try {
                                startActivityForResult(appIntent, STORAGE_PERMISSION_REQUEST)
                            } catch (_: ActivityNotFoundException) {
                                val fallbackIntent =
                                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivityForResult(fallbackIntent, STORAGE_PERMISSION_REQUEST)
                            }
                        } else {
                            pendingStoragePermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    Manifest.permission.READ_EXTERNAL_STORAGE,
                                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                                ),
                                STORAGE_PERMISSION_REQUEST
                            )
                        }
                    } catch (e: Exception) {
                        pendingStoragePermissionResult = null
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "hasStoragePermission" -> {
                    result.success(hasSharedStoragePermission())
                }
                "getExternalStoragePath" -> {
                    result.success(Environment.getExternalStorageDirectory().absolutePath)
                }
                "readRootfsFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        Thread {
                            try {
                                val content = bootstrapManager.readRootfsFile(path)
                                runOnUiThread { result.success(content) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("ROOTFS_READ_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "path required", null)
                    }
                }
                "writeRootfsFile" -> {
                    val path = call.argument<String>("path")
                    val content = call.argument<String>("content")
                    if (path != null && content != null) {
                        Thread {
                            try {
                                bootstrapManager.writeRootfsFile(path, content)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("ROOTFS_WRITE_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "path and content required", null)
                    }
                }
                "bringToForeground" -> {
                    try {
                        val intent = Intent(applicationContext, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        }
                        applicationContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_ERROR", e.message, null)
                    }
                }
                "setWindowSoftInputMode" -> {
                    val mode = call.argument<String>("mode")
                        ?.trim()
                        ?.lowercase()
                        ?: "adjustResize"
                    runOnUiThread {
                        window.setSoftInputMode(
                            when (mode) {
                                "adjustpan", "pan" ->
                                    WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED or
                                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
                                "adjustnothing", "nothing" ->
                                    WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED or
                                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
                                else ->
                                    WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED or
                                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                            }
                        )
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        createUrlNotificationChannel()
        requestNotificationPermission()

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETUP_LOG_EVENT_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    setupLogSink = events
                }

                override fun onCancel(arguments: Any?) {
                    setupLogSink = null
                }
            }
        )
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST
                )
            }
        }
    }

    private fun createUrlNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                URL_CHANNEL_ID,
                "CLI URLs",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for detected URLs"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun getWebViewPackageInfo(): Map<String, Any?> {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WebView.getCurrentWebViewPackage()
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo("com.google.android.webview", 0)
            }
            hashMapOf(
                "packageName" to packageInfo?.packageName,
                "versionName" to packageInfo?.versionName,
                "majorVersion" to parseMajorVersion(packageInfo?.versionName)
            )
        } catch (_: Exception) {
            hashMapOf(
                "packageName" to null,
                "versionName" to null,
                "majorVersion" to null
            )
        }
    }

    private fun getAppPackageInfo(): Map<String, Any?> {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
            hashMapOf(
                "packageName" to packageInfo.packageName,
                "versionName" to packageInfo.versionName,
                "versionCode" to versionCode
            )
        } catch (_: Exception) {
            hashMapOf(
                "packageName" to packageName,
                "versionName" to null,
                "versionCode" to null
            )
        }
    }

    private fun parseMajorVersion(versionName: String?): Int? {
        if (versionName.isNullOrBlank()) {
            return null
        }
        return versionName.substringBefore('.').toIntOrNull()
    }

    private var urlNotificationId = 100

    private fun showUrlNotification(url: String, title: String) {
        val openIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        val openPending = PendingIntent.getActivity(
            this, urlNotificationId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, URL_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(url)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(openPending)
                .setAutoCancel(true)
                .setStyle(Notification.BigTextStyle().bigText(url))
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle(title)
                .setContentText(url)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(openPending)
                .setAutoCancel(true)
                .build()
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(urlNotificationId++, notification)
    }

    private fun hasSharedStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun completeStoragePermissionRequest() {
        val pendingResult = pendingStoragePermissionResult ?: return
        pendingStoragePermissionResult = null
        pendingResult.success(hasSharedStoragePermission())
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            completeStoragePermissionRequest()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            completeStoragePermissionRequest()
            return
        }

        if (requestCode == NATIVE_TERMINAL_ACTIVITY_REQUEST ||
            requestCode == NATIVE_TERMINAL_PAGER_ACTIVITY_REQUEST
        ) {
            pendingNativeTerminalResult?.success(resultCode == Activity.RESULT_OK)
            pendingNativeTerminalResult = null
            return
        }

        if (requestCode == SNAPSHOT_SAVE_REQUEST) {
            val pendingResult = snapshotSaveResult
            val pendingContent = pendingSnapshotContent
            val pendingName = pendingSnapshotName
            snapshotSaveResult = null
            pendingSnapshotContent = null
            pendingSnapshotName = null

            if (pendingResult == null || pendingContent == null || pendingName == null) {
                return
            }

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    contentResolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use {
                        it.write(pendingContent)
                    } ?: throw IllegalStateException("Unable to open destination for writing")

                    pendingResult.success(
                        hashMapOf(
                            "name" to queryDisplayName(uri, pendingName),
                            "uri" to uri.toString()
                        )
                    )
                } catch (e: Exception) {
                    pendingResult.error("SNAPSHOT_SAVE_ERROR", e.message, null)
                }
            } else {
                pendingResult.success(null)
            }
            return
        }

        if (requestCode == BOOTSTRAP_ARCHIVE_PICK_REQUEST) {
            val pendingResult = bootstrapArchivePickResult
            if (pendingResult == null) {
                return
            }

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                Thread {
                    try {
                        val fallbackName =
                            uri.lastPathSegment?.substringAfterLast('/')
                                ?: "openclaw-prebuilt-rootfs.tar.gz"
                        val name = queryDisplayName(uri, fallbackName)
                        val cached = copyBootstrapArchiveToCache(uri, name)
                        runOnUiThread {
                            pendingResult.success(
                                hashMapOf(
                                    "name" to name,
                                    "path" to cached.absolutePath
                                )
                            )
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            pendingResult.error("BOOTSTRAP_ARCHIVE_PICK_ERROR", e.message, null)
                        }
                    } finally {
                        bootstrapArchivePickResult = null
                    }
                }.start()
            } else {
                pendingResult.success(null)
                bootstrapArchivePickResult = null
            }
            return
        }

    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            completeStoragePermissionRequest()
        }
    }

    private fun copyUriToCache(uri: Uri, fileName: String): File {
        val sanitizedName = sanitizeDocumentFileName(fileName)
        val cacheFile = File(
            cacheDir,
            "backup-import-${System.currentTimeMillis()}-$sanitizedName"
        )
        contentResolver.openInputStream(uri)?.use { input ->
            cacheFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open source file")
        return cacheFile
    }

    private fun copyBootstrapArchiveToCache(uri: Uri, fileName: String): File {
        val sanitizedName = sanitizeDocumentFileName(fileName)
        val cacheFile = File(
            cacheDir,
            "bootstrap-archive-${System.currentTimeMillis()}-$sanitizedName"
        )
        contentResolver.openInputStream(uri)?.use { input ->
            cacheFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open source file")
        return cacheFile
    }

    private fun sanitizeDocumentFileName(fileName: String): String {
        val normalized = fileName.trim().ifEmpty { "backup" }
        val sanitized = normalized
            .replace(Regex("[^A-Za-z0-9._-]+"), "-")
            .trim('-')
            .ifEmpty { "backup" }
        return sanitized.take(96)
    }

    private fun queryDisplayName(uri: Uri, fallback: String): String {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            cursor.getString(index) ?: fallback
                        } else {
                            fallback
                        }
                    } else {
                        fallback
                    }
                } ?: fallback
        } catch (_: Exception) {
            fallback
        }
    }

    companion object {
        const val URL_CHANNEL_ID = "openclaw_urls"
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
        const val SCREEN_CAPTURE_REQUEST = 1002
        const val STORAGE_PERMISSION_REQUEST = 1003
        const val SNAPSHOT_PICK_REQUEST = 1004
        const val INSTALL_UNKNOWN_APP_SOURCES_REQUEST = 1005
        const val SNAPSHOT_SAVE_REQUEST = 1006
        const val BACKUP_PICK_REQUEST = 1007
        const val WORKSPACE_BACKUP_SAVE_REQUEST = 1008
        const val BOOTSTRAP_ARCHIVE_PICK_REQUEST = 1009
        const val NATIVE_TERMINAL_ACTIVITY_REQUEST = 1010
        const val NATIVE_TERMINAL_PAGER_ACTIVITY_REQUEST = 1011
    }
}
