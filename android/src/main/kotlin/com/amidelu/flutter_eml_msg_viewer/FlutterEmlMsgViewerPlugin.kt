package com.amidelu.flutter_eml_msg_viewer

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class FlutterEmlMsgViewerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_eml_msg_viewer")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getTempDirectory" -> {
                result.success(context.cacheDir.absolutePath)
            }
            "openFile" -> {
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType")
                if (path == null) {
                    result.error("INVALID_ARGUMENT", "File path cannot be null", null)
                    return
                }

                val file = File(path)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "File does not exist at path: $path", null)
                    return
                }

                try {
                    val authority = "${context.packageName}.flutter_eml_msg_viewer.fileprovider"
                    val uri = FileProvider.getUriForFile(context, authority, file)
                    val resolvedMimeType = resolveMimeType(file, mimeType)

                    // Retry with a wildcard type so any app that accepts the file is offered.
                    val opened = startViewer(uri, resolvedMimeType) ||
                        (resolvedMimeType != "*/*" && startViewer(uri, "*/*"))
                    result.success(opened)
                } catch (e: Exception) {
                    result.error("OPEN_FAILED", e.message ?: e.javaClass.simpleName, null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Prefers the MIME type from the email part, but falls back to the file
     * extension when it is missing or generic (`application/octet-stream`),
     * since viewer apps rarely register for generic types.
     */
    private fun resolveMimeType(file: File, mimeType: String?): String {
        val declared = mimeType?.trim()?.lowercase()
        if (!declared.isNullOrEmpty() && declared != "application/octet-stream" && declared.contains('/')) {
            return declared
        }
        // MimeTypeMap.getFileExtensionFromUrl() returns "" for names with
        // spaces or non-URL characters, so read the extension from the File.
        val extension = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
    }

    private fun startViewer(uri: Uri, mimeType: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
