package blinlin.com

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "blinlin.com/message_alerts"
    private val notificationChannelId = "message_alerts"
    private var pendingLaunchPayload: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingLaunchPayload = intent.getStringExtra("payload") ?: intent.getStringExtra("blinlin_payload")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    createNotificationChannel()
                    requestNotificationPermissionIfNeeded()
                    CallKeepAliveService.start(this)
                    result.success(true)
                }
                "startKeepAlive" -> {
                    createNotificationChannel()
                    requestNotificationPermissionIfNeeded()
                    CallKeepAliveService.start(this)
                    result.success(true)
                }
                "stopKeepAlive" -> {
                    CallKeepAliveService.stop(this)
                    result.success(true)
                }
                "notifyMessage" -> {
                    createNotificationChannel()
                    val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                    val title = call.argument<String>("title") ?: "搭个话消息"
                    val body = call.argument<String>("body") ?: "收到一条新消息"
                    val payload = call.argument<String>("payload")
                    showMessageNotification(id, title, body, payload)
                    result.success(true)
                }
                "getLaunchPayload" -> {
                    val payload = pendingLaunchPayload
                        ?: intent?.getStringExtra("payload")
                        ?: intent?.getStringExtra("blinlin_payload")
                    pendingLaunchPayload = null
                    intent?.removeExtra("payload")
                    intent?.removeExtra("blinlin_payload")
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                notificationChannelId,
                "消息提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "搭个话新消息提醒"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun showMessageNotification(id: Int, title: String, body: String, payload: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermissionIfNeeded()
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val launchIntent = (packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!payload.isNullOrBlank()) {
                putExtra("payload", payload)
                putExtra("blinlin_payload", payload)
            }
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .build()
        manager.notify(id, notification)
    }
}
