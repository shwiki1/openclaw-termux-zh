package com.agent.cyx

import android.media.MediaMetadataRetriever
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import java.io.File
import java.util.Locale

object MediaToolbox {
    data class CommandResult(
        val success: Boolean,
        val message: String,
        val outputFile: File? = null,
    )

    data class MediaInfo(
        val title: String?,
        val artist: String?,
        val album: String?,
        val durationMs: Long?,
        val mimeType: String?,
        val bitrate: Long?,
        val sampleRate: Int?,
        val hasEmbeddedArt: Boolean,
        val embeddedArt: ByteArray?,
    ) {
        fun summaryLines(file: File): List<String> {
            return buildList {
                add("文件: ${file.name}")
                title?.takeIf { it.isNotBlank() }?.let { add("标题: $it") }
                artist?.takeIf { it.isNotBlank() }?.let { add("艺术家: $it") }
                album?.takeIf { it.isNotBlank() }?.let { add("专辑: $it") }
                durationMs?.takeIf { it > 0 }?.let { add("时长: ${formatDuration(it)}") }
                mimeType?.takeIf { it.isNotBlank() }?.let { add("类型: $it") }
                bitrate?.takeIf { it > 0 }?.let { add("码率: ${it / 1000} kbps") }
                sampleRate?.takeIf { it > 0 }?.let { add("采样率: ${it} Hz") }
                add("封面: ${if (hasEmbeddedArt) "有" else "无"}")
                add("大小: ${formatSize(file.length())}")
                add("路径: ${file.absolutePath}")
            }
        }
    }

    fun readMediaInfo(file: File): MediaInfo {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val art = retriever.embeddedPicture
            MediaInfo(
                title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull(),
                mimeType = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
                bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull(),
                sampleRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull(),
                hasEmbeddedArt = art != null,
                embeddedArt = art,
            )
        } finally {
            retriever.release()
        }
    }

    fun convertAudioToMp3(source: File, target: File): CommandResult {
        return runCommand(
            source = source,
            target = target,
            command = "-y -i ${quoted(source)} -vn -codec:a libmp3lame -q:a 2 ${quoted(target)}",
            successMessage = "已转换为 MP3",
        )
    }

    fun convertAudioToM4a(source: File, target: File): CommandResult {
        return runCommand(
            source = source,
            target = target,
            command = "-y -i ${quoted(source)} -vn -codec:a aac -b:a 192k ${quoted(target)}",
            successMessage = "已转换为 M4A",
        )
    }

    fun extractAudioFromVideo(source: File, target: File): CommandResult {
        return runCommand(
            source = source,
            target = target,
            command = "-y -i ${quoted(source)} -vn -codec:a aac -b:a 192k ${quoted(target)}",
            successMessage = "已提取音频",
        )
    }

    fun convertVideoToMp4(source: File, target: File): CommandResult {
        return runCommand(
            source = source,
            target = target,
            command = "-y -i ${quoted(source)} -map 0:v:0 -map 0:a? -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 192k -movflags +faststart ${quoted(target)}",
            successMessage = "已转换为 MP4",
        )
    }

    fun extractVideoFrame(source: File, target: File): CommandResult {
        return runCommand(
            source = source,
            target = target,
            command = "-y -i ${quoted(source)} -vf thumbnail -frames:v 1 ${quoted(target)}",
            successMessage = "已导出封面帧",
        )
    }

    private fun runCommand(
        source: File,
        target: File,
        command: String,
        successMessage: String,
    ): CommandResult {
        if (!source.exists()) {
            return CommandResult(false, "源文件不存在: ${source.name}")
        }
        target.parentFile?.mkdirs()
        val session = FFmpegKit.execute(command)
        val returnCode = session.returnCode
        if (ReturnCode.isSuccess(returnCode) && target.exists()) {
            return CommandResult(true, successMessage, target)
        }
        val detail = session.allLogsAsString.takeIf { it.isNotBlank() }
            ?: session.failStackTrace.takeIf { !it.isNullOrBlank() }
            ?: "未知错误"
        if (target.exists()) {
            target.delete()
        }
        return CommandResult(
            success = false,
            message = "FFmpeg 处理失败: ${detail.lineSequence().lastOrNull()?.trim().orEmpty()}",
        )
    }

    private fun quoted(file: File): String {
        return "\"${file.absolutePath.replace("\"", "\\\"")}\""
    }

    private fun formatSize(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.ROOT, "%.1f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.ROOT, "%.1f MB", mb)
        return String.format(Locale.ROOT, "%.1f GB", mb / 1024.0)
    }

    fun formatDuration(durationMs: Long): String {
        val totalSeconds = durationMs / 1000
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.ROOT, "%02d:%02d", minutes, seconds)
        }
    }
}
