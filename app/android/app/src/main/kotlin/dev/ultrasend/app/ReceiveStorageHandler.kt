package dev.ultrasend.app

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Reserves app-owned Downloads entries before receiving bytes. No staging copy. */
class ReceiveStorageHandler(private val context: Context, messenger: BinaryMessenger) {
    private val resolver = context.contentResolver
    private val pending = context.getSharedPreferences("receive_destinations", Context.MODE_PRIVATE)

    init {
        MethodChannel(messenger, "dev.ultrasend/receive_storage").setMethodCallHandler { call, result ->
            try {
                val key = call.argument<String>("key")
                when (call.method) {
                    "prepare" -> result.success(prepare(requireNotNull(key), requireNotNull(call.argument("name"))))
                    "lookup" -> result.success(lookup(requireNotNull(key)))
                    "owns" -> result.success(pending.all.values.any { value ->
                        if (value !is String) false else JSONObject(value).let {
                            it.optString("path") == call.argument<String>("path") || it.optString("finalPath") == call.argument<String>("path")
                        }
                    })
                    "complete" -> result.success(complete(requireNotNull(call.argument("path")), requireNotNull(call.argument<Number>("expectedSize")).toLong()))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("RECEIVE_DESTINATION", error.message, null)
            }
        }
    }

    private fun storageKey(key: String): String = MessageDigest.getInstance("SHA-256")
        .digest(key.toByteArray()).joinToString("") { "%02x".format(it) }

    private fun lookup(key: String): String? {
        val saved = pending.getString(storageKey(key), null) ?: return null
        val record = JSONObject(saved)
        if (record.optBoolean("done", false)) return null
        val path = record.getString("path")
        if (File(path).exists()) return path
        pending.edit().remove(storageKey(key)).commit()
        return null
    }

    @Synchronized
    private fun prepare(key: String, name: String): String? {
        // Android 10's MediaStore does not expose direct File API access.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val preferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!preferences.getString("flutter.ultrasend_custom_save_tree_uri", null).isNullOrEmpty()) return null
        lookup(key)?.let { return it }
        val safeName = name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").trim().ifEmpty { "received" }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("无法创建下载文件")
        try {
            // Allocate the file through MediaStore so scoped storage attributes it to this app.
            resolver.openFileDescriptor(uri, "rw")?.close() ?: error("无法打开下载文件")
            @Suppress("DEPRECATION")
            val path = resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: error("无法获取下载文件地址")
            check(File(path).canWrite()) { "下载目录不可写" }
            val record = JSONObject().put("uri", uri.toString()).put("path", path)
            check(pending.edit().putString(storageKey(key), record.toString()).commit())
            return path
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Synchronized
    private fun complete(path: String, expectedSize: Long): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        for ((key, value) in pending.all) {
            if (value !is String) continue
            val record = JSONObject(value)
            if (record.getString("path") != path && record.optString("finalPath") != path) continue
            val readable = record.optString("finalPath").ifEmpty { path }
            check(File(readable).length() == expectedSize) { "接收文件不完整" }
            val uri = Uri.parse(record.getString("uri"))
            val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            check(resolver.update(uri, values, null, null) > 0) { "无法完成下载文件" }
            // Publishing removes MediaStore's .pending prefix from the path.
            @Suppress("DEPRECATION")
            val finalPath = resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: error("无法获取已完成文件地址")
            // Keep the completion receipt so a crash before the Dart database
            // update can retry finalization without creating a second copy.
            pending.edit().putString(key, record.put("done", true).put("finalPath", finalPath).toString()).commit()
            return finalPath
        }
        return null
    }
}
