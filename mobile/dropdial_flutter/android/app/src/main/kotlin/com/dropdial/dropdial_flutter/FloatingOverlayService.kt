package com.dropdial.dropdial_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView

class FloatingOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    companion object {
        const val CHANNEL_ID = "dropdial_overlay_channel"
        const val NOTIFICATION_ID = 1001
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        showFloatingDock()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DropDial Edge Dock",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the floating edge dock active for instant radial conversions"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("DropDial Floating Edge Active")
            .setContentText("Swipe or tap edge pill to summon radial dial")
            .setSmallIcon(android.R.drawable.ic_menu_rotate)
            .build()
    }

    private fun showFloatingDock() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            dpToPx(48),
            dpToPx(72),
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            x = 0
            y = 0
        }

        // Floating pill container with sleek cyber gradient
        val pill = FrameLayout(this).apply {
            val backgroundShape = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadii = floatArrayOf(
                    dpToPx(16).toFloat(), dpToPx(16).toFloat(),
                    0f, 0f,
                    0f, 0f,
                    dpToPx(16).toFloat(), dpToPx(16).toFloat()
                )
                setColor(Color.parseColor("#E614181E"))
                setStroke(dpToPx(2), Color.parseColor("#00E5FF"))
            }
            background = backgroundShape

            val icon = ImageView(this@FloatingOverlayService).apply {
                setImageResource(android.R.drawable.ic_menu_rotate)
                setColorFilter(Color.parseColor("#00E5FF"))
                layoutParams = FrameLayout.LayoutParams(
                    dpToPx(24),
                    dpToPx(24),
                    Gravity.CENTER
                )
            }
            addView(icon)
        }

        // Touch & Drag listener
        pill.setOnTouchListener(object : View.OnTouchListener {
            private var initialY = 0
            private var initialTouchY = 0f
            private var isDragging = false

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialY = params.y
                        initialTouchY = event.rawY
                        isDragging = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dy = (event.rawY - initialTouchY).toInt()
                        if (Math.abs(dy) > 10) {
                            isDragging = true
                            params.y = initialY + dy
                            windowManager?.updateViewLayout(overlayView, params)
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            // Tap triggered -> Summon DropDial!
                            val launchIntent = Intent(this@FloatingOverlayService, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            startActivity(launchIntent)
                        }
                        return true
                    }
                }
                return false
            }
        })

        overlayView = pill
        windowManager?.addView(overlayView, params)
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        super.onDestroy()
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
        }
    }
}

