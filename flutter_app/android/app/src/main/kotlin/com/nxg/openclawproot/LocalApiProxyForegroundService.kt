package com.agent.cyx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.io.File
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

class LocalApiProxyForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "openclaw_local_api_proxy"
        const val NOTIFICATION_ID = 11
        const val PORT = 9999
        private const val GUEST_DIR = "/root/.openclaw/api2py"
        private const val LOG_PATH = "$GUEST_DIR/server.log"
        private const val PID_PATH = "$GUEST_DIR/server.pid"

        var isRunning = false
            private set

        private var instance: LocalApiProxyForegroundService? = null

        fun start(context: Context) {
            val intent = Intent(context, LocalApiProxyForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocalApiProxyForegroundService::class.java))
        }
    }

    private var proxyProcess: Process? = null
    private var outputThread: Thread? = null
    private var errorThread: Thread? = null
    private var workerThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Starting local API proxy on port $PORT"))
        if (isRunning && workerThread?.isAlive == true) {
            updateNotification(runningStatus())
            return START_REDELIVER_INTENT
        }
        acquireWakeLock()
        startProxySupervisor()
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        workerThread?.interrupt()
        workerThread = null
        stopProxyProcess()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startProxySupervisor() {
        if (workerThread?.isAlive == true) return
        isRunning = true
        instance = this
        workerThread = Thread {
            val filesDir = applicationContext.filesDir.absolutePath
            val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
            val bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)
            val processManager = ProcessManager(filesDir, nativeLibDir)
            var restartCount = 0
            val maxRestarts = 4

            while (isRunning && !Thread.currentThread().isInterrupted) {
                try {
                    bootstrapManager.setupDirectories()
                    bootstrapManager.writeResolvConf()
                    proxyProcess = processManager.startProotProcess(buildProxyCommand())
                    outputThread = drainStream(proxyProcess!!.inputStream, "LocalApiProxyStdout")
                    errorThread = drainStream(proxyProcess!!.errorStream, "LocalApiProxyStderr")
                    if (waitForStarted(20_000L)) {
                        restartCount = 0
                        updateNotification(runningStatus())
                    } else {
                        updateNotification("Local API proxy warming up or missing health response")
                    }

                    val exitCode = proxyProcess!!.waitFor()
                    stopProxyProcess()
                    if (!isRunning) break
                    restartCount++
                    if (restartCount > maxRestarts) {
                        isRunning = false
                        updateNotification("Local API proxy stopped (exit $exitCode)")
                        stopSelf()
                        break
                    }
                    updateNotification("Local API proxy exited, restarting ($restartCount/$maxRestarts)")
                    Thread.sleep(1500L * restartCount)
                } catch (_: InterruptedException) {
                    break
                } catch (error: Exception) {
                    stopProxyProcess()
                    if (!isRunning) break
                    restartCount++
                    updateNotification("Local API proxy error: ${error.message?.take(56) ?: "unknown"}")
                    if (restartCount > maxRestarts) {
                        isRunning = false
                        stopSelf()
                        break
                    }
                    try {
                        Thread.sleep(1500L * restartCount)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
        }.apply {
            name = "LocalApiProxyForegroundWorker"
            start()
        }
    }

    private fun buildProxyCommand(): String = """
        set -eu
        cd ${shellQuote(GUEST_DIR)}
        mkdir -p data/sessions
        if [ ! -f data/config.json ] && [ -f data/config.example.json ]; then
          cp data/config.example.json data/config.json
        fi
        chmod +x start.sh stop.sh 2>/dev/null || true
        if [ ! -f app/__init__.py ] || [ ! -f app/main.py ] || [ ! -f app/config.py ]; then
          echo "api2py bundled files are incomplete" >&2
          exit 1
        fi
        python3 - <<'PY'
for module in ('starlette', 'uvicorn', 'httpx', 'aiosqlite'):
    __import__(module)
PY
        rm -f ${shellQuote(PID_PATH)} ${shellQuote(LOG_PATH)}
        export HOST=127.0.0.1 PORT=$PORT WORKERS=1
        printf '%s\n' "${'$'}${'$'}" > ${shellQuote(PID_PATH)}
        exec python3 server.py >> ${shellQuote(LOG_PATH)} 2>&1
    """.trimIndent()

    private fun stopProxyProcess() {
        proxyProcess?.let {
            try {
                it.destroy()
            } catch (_: Exception) {}
            try {
                it.destroyForcibly()
            } catch (_: Exception) {}
        }
        proxyProcess = null
        outputThread?.interrupt()
        outputThread = null
        errorThread?.interrupt()
        errorThread = null
    }

    private fun drainStream(input: InputStream, threadName: String): Thread {
        return Thread {
            val buffer = ByteArray(4096)
            try {
                while (!Thread.currentThread().isInterrupted) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                }
            } catch (_: Exception) {}
        }.apply {
            name = threadName
            isDaemon = true
            start()
        }
    }

    private fun waitForStarted(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (isRunning && System.currentTimeMillis() < deadline) {
            if (isPortOpen(PORT)) return true
            Thread.sleep(500)
        }
        return false
    }

    private fun runningStatus(): String {
        return if (isPortOpen(PORT)) {
            "Local API proxy running on port $PORT"
        } else {
            "Local API proxy process running, waiting for port $PORT"
        }
    }

    private fun isPortOpen(port: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1000)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "CiYuanXia::LocalApiProxyWakeLock"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L)
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "CiYuanXia local API proxy",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the local API relay running in the background"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("CiYuanXia API Proxy")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun shellQuote(value: String): String {
        return "'" + value.replace("'", "'\\''") + "'"
    }
}
