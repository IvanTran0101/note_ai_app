package com.example.note_ai_app

import android.content.ContentValues
import android.content.Context
import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.OutputStream
import java.util.UUID

/** Deliberate owner export. Incomplete Downloads entries stay pending and are
 * deleted on cancel/failure; source bytes arrive in bounded authorized chunks. */
class AttachmentExports(private val context: Context) {
    private data class Pending(val uri: Uri, val stream: OutputStream, val size: Long, var written: Long = 0)
    private val pending = mutableMapOf<String, Pending>()
    private var recovered = false

    fun install(messenger: BinaryMessenger) {
        MethodChannel(messenger, "noteflow/attachment_export", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result -> handle(call, result) }
    }

    @Synchronized private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        try {
            if (!recovered) {recoverAbandoned(); recovered = true}
            when (call.method) {
                "begin" -> result.success(begin(call))
                "write" -> {
                    val record = pending[id] ?: error("Unknown export")
                    val bytes = call.argument<ByteArray>("bytes") ?: error("Invalid bytes")
                    require(bytes.isNotEmpty() && bytes.size <= 256 * 1024 && record.written + bytes.size <= record.size)
                    try {record.stream.write(bytes); record.written += bytes.size}
                    finally {bytes.fill(0)}
                    result.success(null)
                }
                "finish" -> {
                    val record = pending[id] ?: error("Unknown export")
                    require(record.written == record.size)
                    record.stream.flush(); record.stream.close()
                    val values = ContentValues().apply {put(MediaStore.MediaColumns.IS_PENDING, 0)}
                    check(context.contentResolver.update(record.uri, values, null, null) == 1)
                    pending.remove(id); result.success(null)
                }
                "cancel" -> {cancel(id); result.success(null)}
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            cancel(id)
            result.error("EXPORT_UNAVAILABLE", "Attachment export could not be completed.", null)
        }
    }

    private fun begin(call: MethodCall): String {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        require(pending.size < 2)
        val name = call.argument<String>("fileName") ?: error("Missing name")
        val mime = call.argument<String>("mimeType") ?: error("Missing type")
        val size = call.argument<Number>("sizeBytes")?.toLong() ?: error("Missing size")
        require(name.isNotBlank() && name.length <= 255 && !name.any { it == '/' || it == '\\' || it.code < 32 || it.code == 127 })
        require(mime in setOf("image/jpeg", "image/png", "image/webp", "video/mp4", "application/pdf", "text/plain", "text/csv"))
        require(size in 1..50L * 1024 * 1024)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/NoteFlow")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("No destination")
        try {
            val stream = context.contentResolver.openOutputStream(uri, "w") ?: error("No stream")
            val id = UUID.randomUUID().toString(); pending[id] = Pending(uri, stream, size); return id
        } catch (e: Exception) {context.contentResolver.delete(uri, null, null); throw e}
    }

    private fun cancel(id: String?) {
        val record = pending.remove(id) ?: return
        runCatching {record.stream.close()}
        runCatching {context.contentResolver.delete(record.uri, null, null)}
    }
    /** Only this package's unpublished exports in its dedicated Downloads
     * folder; completed deliberate exports are never removed. */
    private fun recoverAbandoned() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val selection = "${MediaStore.MediaColumns.IS_PENDING}=1 AND ${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.OWNER_PACKAGE_NAME}=?"
        context.contentResolver.query(collection, arrayOf(MediaStore.MediaColumns._ID), selection,
            arrayOf(Environment.DIRECTORY_DOWNLOADS + "/NoteFlow/", context.packageName), null)?.use {cursor ->
            val column = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(column))
                context.contentResolver.delete(uri, selection, arrayOf(Environment.DIRECTORY_DOWNLOADS + "/NoteFlow/", context.packageName))
            }
        }
    }
    @Synchronized fun close() {pending.keys.toList().forEach {cancel(it)}}
}
