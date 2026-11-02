package com.dropdial.dropdial_flutter

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import java.io.File
import java.io.FileOutputStream

class DropDialAccessibilityService : AccessibilityService() {

    private var isVolUpPressed = false
    private var isVolDownPressed = false
    private val handler = Handler(Looper.getMainLooper())
    private var chordRunnable: Runnable? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {
        cancelChord()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val action = event.action
        val keyCode = event.keyCode

        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (action == KeyEvent.ACTION_DOWN) {
                isVolUpPressed = true
                checkChordTrigger()
            } else if (action == KeyEvent.ACTION_UP) {
                isVolUpPressed = false
                cancelChord()
            }
        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (action == KeyEvent.ACTION_DOWN) {
                isVolDownPressed = true
                checkChordTrigger()
            } else if (action == KeyEvent.ACTION_UP) {
                isVolDownPressed = false
                cancelChord()
            }
        }

        return super.onKeyEvent(event)
    }

    private fun checkChordTrigger() {
        if (isVolUpPressed && isVolDownPressed) {
            if (chordRunnable == null) {
                chordRunnable = Runnable {
                    triggerDropDialFromChord()
                }
                // Require 0.5s simultaneous hold to avoid false triggers
                handler.postDelayed(chordRunnable!!, 500)
            }
        }
    }

    private fun cancelChord() {
        chordRunnable?.let {
            handler.removeCallbacks(it)
            chordRunnable = null
        }
    }

    private fun triggerDropDialFromChord() {
        cancelChord()
        isVolUpPressed = false
        isVolDownPressed = false

        // 1. Try to find image or file in Clipboard
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        var filePath: String? = null

        val clip = clipboard?.primaryClip
        if (clip != null && clip.itemCount > 0) {
            val item = clip.getItemAt(0)
            item.uri?.let { uri ->
                filePath = copyUriToCache(uri)
            }
        }

        // 2. If no clipboard file, check for latest photo / screenshot in MediaStore
        if (filePath == null) {
            filePath = getLatestMediaFilePath()
        }

        // 3. Launch DropDial with the file
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (filePath != null) {
                putStringArrayListExtra("shared_files", arrayListOf(filePath))
            }
        }
        startActivity(intent)
    }

    private fun getLatestMediaFilePath(): String? {
        return try {
            val projection = arrayOf(MediaStore.Images.Media.DATA)
            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val columnIndex = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                    it.getString(columnIndex)
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val fileName = "clip_${System.currentTimeMillis()}"
            val cacheFile = File(cacheDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }
}

