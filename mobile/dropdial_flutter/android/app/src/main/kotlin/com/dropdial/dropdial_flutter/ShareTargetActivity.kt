package com.dropdial.dropdial_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.io.File
import java.io.FileOutputStream

/**
 * Trampoline activity for system Share Sheet (ACTION_SEND & ACTION_SEND_MULTIPLE).
 * Receives shared file URIs, caches them locally, and forwards to MainActivity.
 */
class ShareTargetActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val paths = arrayListOf<String>()

        when (intent?.action) {
            Intent.ACTION_SEND -> {
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uri ->
                    copyUriToCache(uri)?.let { paths.add(it) }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.forEach { uri ->
                    copyUriToCache(uri)?.let { paths.add(it) }
                }
            }
        }

        val mainIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putStringArrayListExtra("shared_files", paths)
        }
        startActivity(mainIntent)
        finish()
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val contentResolver = applicationContext.contentResolver
            val fileName = getFileName(uri) ?: "shared_${System.currentTimeMillis()}"
            val cacheFile = File(cacheDir, fileName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        name = it.getString(index)
                    }
                }
            }
        }
        if (name == null) {
            name = uri.path
            val cut = name?.lastIndexOf('/')
            if (cut != null && cut != -1) {
                name = name?.substring(cut + 1)
            }
        }
        return name
    }
}
