package com.dropdial.dropdial_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val INTAKE_CHANNEL = "com.dropdial.mobile/intake"
    private val SYSTEM_CHANNEL = "com.dropdial.mobile/system"

    private var initialSharedFiles: ArrayList<String>? = null
    private var intakeChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        val files = intent.getStringArrayListExtra("shared_files")
        if (files != null && files.isNotEmpty()) {
            intakeChannel?.invokeMethod("onFilesReceived", files)
        }
    }

    private fun handleIntent(intent: Intent?) {
        intent?.getStringArrayListExtra("shared_files")?.let {
            initialSharedFiles = it
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        intakeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTAKE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedFiles" -> {
                        val files = initialSharedFiles ?: arrayListOf<String>()
                        initialSharedFiles = null // Clear once consumed
                        result.success(files)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "canDrawOverlays" -> {
                        val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this@MainActivity)
                        } else {
                            true
                        }
                        result.success(canDraw)
                    }
                    "openOverlaySettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "toggleFloatingOverlay" -> {
                        val enable = call.argument<Boolean>("enabled") ?: false
                        val serviceIntent = Intent(this@MainActivity, FloatingOverlayService::class.java)
                        if (enable) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                        } else {
                            stopService(serviceIntent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedService = "$packageName/${DropDialAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentName = colonSplitter.next()
            if (componentName.equals(expectedService, ignoreCase = true)) {
                return true
            }
        }
        return false
    }
}
