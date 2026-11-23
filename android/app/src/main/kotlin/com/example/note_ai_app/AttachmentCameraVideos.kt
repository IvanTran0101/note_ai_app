package com.example.note_ai_app

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Normalize only this app's camera scratch video. No user originals, network,
 * decrypted note cache, or broad codec conversion is accepted by this port. */
class AttachmentCameraVideos(private val context: Context) {
    private val closed = AtomicBoolean(false)
    private val directory get() = File(context.cacheDir, "attachment-camera")
    private var recovered = false

    fun install(messenger: BinaryMessenger) {
        MethodChannel(messenger, "noteflow/attachment_camera_video", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            if (call.method != "prepare") {result.notImplemented(); return@setMethodCallHandler}
            try {
                if (!recovered) {recoverScratch(); recovered = true}
                result.success(prepare(call.argument<String>("path") ?: error("Missing selection")))
            } catch (_: Exception) {
                result.error("CAMERA_VIDEO_UNAVAILABLE", "Camera video could not be prepared. Choose a supported MP4 from Files or Gallery.", null)
            }
        }
    }

    private fun prepare(path: String): String {
        val source = File(path).canonicalFile
        require(source.path.startsWith(context.cacheDir.canonicalPath + File.separator))
        require(source.isFile && source.length() in 1..MAX_BYTES)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(source.path)
            val formats = (0 until extractor.trackCount).map {extractor.getTrackFormat(it)}
            val video = formats.indexOfFirst {it.getString(MediaFormat.KEY_MIME) == "video/avc"}
            val audio = formats.indexOfFirst {it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true}
            if (video < 0 || audio < 0 || formats[audio].getString(MediaFormat.KEY_MIME) !in setOf("audio/3gpp", "audio/amr-wb")) return source.path
            require(formats.size == 2)
            directory.mkdirs()
            val id = UUID.randomUUID().toString()
            val sound = File(directory, "$id.audio.mp4")
            val output = File(directory, "$id.mp4")
            val deadline = SystemClock.elapsedRealtime() + 90_000
            val guard = {check(!closed.get() && SystemClock.elapsedRealtime() < deadline)}
            try {
                AttachmentCameraAudio.transcode(source, audio, formats[audio], sound, guard)
                mux(source, video, formats[video], sound, output, guard)
                guard(); require(output.length() in 1..MAX_BYTES)
                return output.path
            } catch (e: Exception) {output.delete(); throw e}
            finally {sound.delete()}
        } finally {extractor.release()}
    }

    private fun mux(source: File, video: Int, format: MediaFormat, sound: File, output: File, guard: () -> Unit) {
        val image = MediaExtractor(); val audio = MediaExtractor()
        var writing: MediaMuxer? = null
        var started = false
        try {
            val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also {writing = it}
            image.setDataSource(source.path); image.selectTrack(video)
            audio.setDataSource(sound.path); audio.selectTrack(0)
            val videoTrack = muxer.addTrack(format)
            val audioTrack = muxer.addTrack(audio.getTrackFormat(0))
            if (format.containsKey(MediaFormat.KEY_ROTATION)) muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
            muxer.start(); started = true
            copy(image, muxer, videoTrack, output, guard)
            copy(audio, muxer, audioTrack, output, guard)
            muxer.stop(); started = false
        } finally {
            if (started) runCatching {writing?.stop()}
            runCatching {writing?.release()}; image.release(); audio.release()
        }
    }

    private fun copy(source: MediaExtractor, muxer: MediaMuxer, track: Int, output: File, guard: () -> Unit) {
        val buffer = ByteBuffer.allocateDirect(1024 * 1024)
        val info = MediaCodec.BufferInfo()
        while (source.sampleTime >= 0) {
            guard(); require(output.length() <= MAX_BYTES)
            buffer.clear()
            val size = source.readSampleData(buffer, 0)
            require(size in 1..buffer.capacity())
            info.set(0, size, source.sampleTime, source.sampleFlags)
            muxer.writeSampleData(track, buffer, info)
            if (!source.advance()) break
        }
    }

    private fun recoverScratch() {
        val root = directory.canonicalFile
        root.listFiles()?.forEach {file ->
            if (file.canonicalFile.parentFile == root && file.name.matches(Regex("[a-f0-9-]{36}(\\.audio)?\\.mp4"))) file.delete()
        }
    }

    fun close() {closed.set(true)}
    companion object {const val MAX_BYTES = 50L * 1024 * 1024}
}
