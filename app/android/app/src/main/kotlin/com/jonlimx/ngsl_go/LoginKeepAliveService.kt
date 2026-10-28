package com.jonlimx.ngsl_go

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** Keeps the user-started OAuth listener alive while the browser is foreground. */
class LoginKeepAliveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val expiry = Runnable { stopSelf() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "chatgpt_login"
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(channelId, "ChatGPT 登录", NotificationManager.IMPORTANCE_LOW)
        )
        val returnToApp = Intent(this, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val notification = Notification.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_login_notification)
            .setContentTitle("正在连接 ChatGPT")
            .setContentText("请完成浏览器授权，然后返回 NGSL Go。")
            .setContentIntent(PendingIntent.getActivity(this, 0, returnToApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(14551, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(14551, notification)
        }
        handler.removeCallbacks(expiry)
        // Also expires if the Dart engine stops unexpectedly. No persistent service.
        handler.postDelayed(expiry, 6 * 60 * 1000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(expiry)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
