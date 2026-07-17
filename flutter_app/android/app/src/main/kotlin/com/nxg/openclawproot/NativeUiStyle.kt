package com.agent.cyx

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable

internal object NativeUiPalette {
    val background = Color.parseColor("#0A0A0A")
    val surface = Color.parseColor("#121212")
    val surfaceAlt = Color.parseColor("#1A1A1A")
    val surfaceRaised = Color.parseColor("#202020")
    val border = Color.parseColor("#2A2A2A")
    val borderStrong = Color.parseColor("#3A3A3A")
    val accent = Color.parseColor("#DC2626")
    val accentPressed = Color.parseColor("#B91C1C")
    val accentSoft = Color.parseColor("#42DC2626")
    val textPrimary = Color.parseColor("#F5F5F5")
    val textMuted = Color.parseColor("#A1A1AA")
    val textSubtle = Color.parseColor("#71717A")
    val success = Color.parseColor("#22C55E")
    val warning = Color.parseColor("#F59E0B")
    val dangerSoft = Color.parseColor("#FCA5A5")
    val successSoft = Color.parseColor("#BBF7D0")
}

internal fun Context.nativeDp(value: Int): Int =
    (value * resources.displayMetrics.density).toInt()

internal fun Context.nativeCardDrawable(
    fillColor: Int,
    strokeColor: Int = NativeUiPalette.border,
    radiusDp: Int = 16,
    strokeWidthDp: Int = 1,
): GradientDrawable =
    GradientDrawable().apply {
        cornerRadius = nativeDp(radiusDp).toFloat()
        setColor(fillColor)
        setStroke(nativeDp(strokeWidthDp).coerceAtLeast(1), strokeColor)
    }

