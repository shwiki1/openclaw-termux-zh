package com.openclaw.cyx

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class OpenClawNativeTerminalViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val channelId = params?.get("viewId") as? String ?: viewId.toString()
        return OpenClawNativeTerminalView(context, messenger, channelId)
    }
}

class OpenClawNativeTerminalView(
    context: Context,
    messenger: BinaryMessenger,
    channelId: String,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val scrollView = ScrollView(context)
    private val textView = TextView(context)
    private val channel = MethodChannel(
        messenger,
        "com.openclaw.cyx/native_terminal/$channelId",
    )

    init {
        textView.setTextColor(Color.rgb(230, 237, 243))
        textView.setBackgroundColor(Color.rgb(6, 10, 18))
        textView.typeface = Typeface.MONOSPACE
        textView.textSize = 11f
        textView.includeFontPadding = false
        textView.setTextIsSelectable(true)
        textView.setPadding(10, 8, 10, 8)
        scrollView.setBackgroundColor(Color.rgb(6, 10, 18))
        scrollView.isFillViewport = true
        scrollView.addView(
            textView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = scrollView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        scrollView.removeAllViews()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setText" -> {
                textView.text = call.argument<String>("text").orEmpty()
                scrollToBottom()
                result.success(true)
            }
            "appendText" -> {
                textView.append(call.argument<String>("text").orEmpty())
                scrollToBottom()
                result.success(true)
            }
            "clear" -> {
                textView.text = ""
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun scrollToBottom() {
        scrollView.post {
            scrollView.fullScroll(View.FOCUS_DOWN)
        }
    }
}
