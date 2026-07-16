package com.agent.cyx

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeTerminalViewFactory(
    private val messenger: BinaryMessenger,
    private val appContext: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>) ?: emptyMap<String, Any?>()
        return NativeTerminalPlatformView(context, appContext, messenger, viewId, params)
    }
}

class NativeTerminalPlatformView(
    context: Context,
    private val appContext: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val params: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.agent.cyx/native_terminal_$viewId")
    private val terminalSessionView = NativeTerminalSessionView(
        context = context,
        appContext = appContext,
        config = params.toNativeTerminalSessionConfig(),
        callbacks = object : NativeTerminalSessionCallbacks {
            override fun onOutput(output: String) {
                channel.invokeMethod("onOutput", output)
            }

            override fun onTitleChanged(title: String) {
                channel.invokeMethod("onTitleChanged", title)
            }

            override fun onSessionFinished(exitStatus: Int) {
                channel.invokeMethod("onSessionFinished", exitStatus)
            }
        },
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun getView() = terminalSessionView

    override fun dispose() {
        terminalSessionView.dispose(closeSession = !terminalSessionView.config.keepAlive)
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeBytes" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.error("INVALID_ARGS", "writeBytes requires Uint8List", null)
                } else {
                    terminalSessionView.writeBytes(bytes)
                    result.success(true)
                }
            }
            "writeText" -> {
                terminalSessionView.writeText(call.argument<String>("text") ?: "")
                result.success(true)
            }
            "paste" -> {
                terminalSessionView.paste()
                result.success(true)
            }
            "showKeyboard" -> {
                terminalSessionView.showKeyboard()
                result.success(true)
            }
            "hideKeyboard" -> {
                terminalSessionView.hideKeyboard()
                result.success(true)
            }
            "setFontSize" -> {
                val nextFontSize = (call.argument<Number>("fontSize")?.toInt()
                    ?: terminalSessionView.config.fontSize)
                terminalSessionView.applyFontSize(nextFontSize)
                result.success(nextFontSize)
            }
            "setRenderingPaused" -> {
                terminalSessionView.setRenderingPaused(call.argument<Boolean>("paused") == true)
                result.success(true)
            }
            "restart" -> {
                terminalSessionView.restart()
                result.success(true)
            }
            "close" -> {
                terminalSessionView.closeSession()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}

private fun Map<*, *>.toNativeTerminalSessionConfig(): NativeTerminalSessionConfig {
    val executable = stringValue("executable")
        ?: throw IllegalArgumentException("Native terminal requires executable")
    return NativeTerminalSessionConfig(
        sessionId = stringValue("sessionId") ?: "native-shell",
        title = stringValue("title") ?: "Terminal",
        executable = executable,
        cwd = stringValue("cwd") ?: "/",
        arguments = stringListValue("arguments"),
        environment = stringMapValue("environment"),
        restart = booleanValue("restart", false),
        keepAlive = booleanValue("keepAlive", false),
        emitOutput = booleanValue("emitOutput", false),
        renderingPaused = booleanValue("renderingPaused", false),
        useNativeToolbar = booleanValue("useNativeToolbar", false),
        transcriptRows = intValue("transcriptRows", 3000),
        fontSize = intValue("fontSize", 18),
    )
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
