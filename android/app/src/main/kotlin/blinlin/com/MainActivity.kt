package blinlin.com

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.util.Rational
import android.content.ContentUris
import android.content.ContentValues
import android.database.Cursor
import android.database.ContentObserver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileWriter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "blinlin.com/message_alerts"
    private val diagnosticsChannelName = "blinlin.com/diagnostics"
    private val screenshotChannelName = "blinlin.com/screenshot_monitor"
    private val appUpdateChannelName = "blinlin.com/app_update"
    private val notificationChannelId = "message_alerts"
    private val callNotificationChannelId = "call_alerts"
    private var pendingLaunchPayload: String? = null
    private var screenshotChannel: MethodChannel? = null
    private var screenshotObserver: ContentObserver? = null
    private var lastScreenshotAt: Long = 0L

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
                "notifyCall" -> {
                    createNotificationChannel()
                    val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                    val title = call.argument<String>("title") ?: "搭个话来电"
                    val body = call.argument<String>("body") ?: "收到音视频来电"
                    val payload = call.argument<String>("payload")
                    showCallNotification(id, title, body, payload)
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
                "enterPictureInPicture" -> {
                    result.success(enterCallPictureInPicture())
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "appendLog" -> {
                    val line = call.argument<String>("line") ?: ""
                    result.success(appendDiagnosticLog(line))
                }
                "getLogPath" -> {
                    result.success(diagnosticLogFile().absolutePath)
                }
                else -> result.notImplemented()
            }
        }
        screenshotChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenshotChannelName)
        screenshotChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startScreenshotObserver()
                    result.success(true)
                }
                "stop" -> {
                    stopScreenshotObserver()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdateChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    installApk(path, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopScreenshotObserver()
        super.onDestroy()
    }

    private fun diagnosticLogFile(): File {
        val external = getExternalFilesDir(null)
        return if (external != null) File(external, "blinlin_call.log") else File(filesDir, "blinlin_call.log")
    }

    private fun diagnosticLogFiles(): List<File> {
        val files = mutableListOf<File>()
        files.add(diagnosticLogFile())
        files.add(File(filesDir, "blinlin_call.log"))
        return files.distinctBy { it.absolutePath }
    }

    private fun appendDiagnosticLog(line: String): Boolean {
        if (line.isBlank()) return false
        var written = false
        for (file in diagnosticLogFiles()) {
            if (appendDiagnosticLogFile(file, line)) written = true
        }
        if (appendPublicDownloadLog(line)) written = true
        return written
    }

    private fun appendDiagnosticLogFile(file: File, line: String): Boolean {
        return try {
            file.parentFile?.mkdirs()
            if (file.exists() && file.length() > 2L * 1024L * 1024L) {
                val rotated = File(file.parentFile, "blinlin_call.log.1")
                if (rotated.exists()) rotated.delete()
                file.renameTo(rotated)
            }
            FileWriter(file, true).use { writer ->
                writer.append(line.take(8000)).append('\n')
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun appendPublicDownloadLog(line: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return try {
                val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                appendDiagnosticLogFile(File(downloads, "blinlin_call.log"), line)
            } catch (_: Throwable) {
                false
            }
        }
        return try {
            val resolver = contentResolver
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val relativePath = Environment.DIRECTORY_DOWNLOADS + "/"
            val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE)
            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?"
            var existingUri: Uri? = null
            resolver.query(collection, projection, selection, arrayOf("blinlin_call.log", relativePath), null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(0)
                    val size = cursor.getLong(1)
                    existingUri = ContentUris.withAppendedId(collection, id)
                    if (size > 2L * 1024L * 1024L) {
                        resolver.delete(existingUri!!, null, null)
                        existingUri = null
                    }
                }
            }
            val uri = existingUri ?: resolver.insert(
                collection,
                ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, "blinlin_call.log")
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
            ) ?: return false
            resolver.openOutputStream(uri, "wa")?.use { stream ->
                stream.write((line.take(8000) + "\n").toByteArray(Charsets.UTF_8))
            } ?: return false
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (path.isBlank()) {
            result.error("bad_args", "安装包路径为空", null)
            return
        }
        val apk = File(path)
        if (!apk.exists() || !apk.isFile) {
            result.error("not_found", "安装包不存在", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(settingsIntent)
                result.error("install_permission", "请允许安装未知来源应用后再次点击更新", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Throwable) {
            result.error("install_failed", e.message ?: "打开安装程序失败", null)
        }
    }

    private fun enterCallPictureInPicture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Throwable) {
            false
        }
    }

    private fun startScreenshotObserver() {
        if (screenshotObserver != null) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                checkLatestScreenshot(uri)
            }
        }
        screenshotObserver = observer
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer
        )
    }

    private fun stopScreenshotObserver() {
        screenshotObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Throwable) {
            }
        }
        screenshotObserver = null
    }

    private fun checkLatestScreenshot(uri: Uri?) {
        val now = System.currentTimeMillis()
        if (now - lastScreenshotAt < 1200L) return
        val projection = arrayOf(
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.RELATIVE_PATH,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED
        )
        val targetUri = uri ?: MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        try {
            contentResolver.query(
                targetUri,
                projection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return
                val name = cursor.getStringOrNullCompat(MediaStore.Images.Media.DISPLAY_NAME)
                val relativePath = cursor.getStringOrNullCompat(MediaStore.Images.Media.RELATIVE_PATH)
                val dataPath = cursor.getStringOrNullCompat(MediaStore.Images.Media.DATA)
                val joined = listOfNotNull(name, relativePath, dataPath).joinToString("/").lowercase()
                if (joined.contains("screenshot") || joined.contains("screenshots") || joined.contains("截屏") || joined.contains("截图")) {
                    lastScreenshotAt = now
                    screenshotChannel?.invokeMethod("onScreenshot", mapOf("time" to now))
                }
            }
        } catch (_: Throwable) {
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

            val callChannel = NotificationChannel(
                callNotificationChannelId,
                "音视频来电",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "搭个话音视频来电提醒"
                enableVibration(true)
                setSound(android.provider.Settings.System.DEFAULT_RINGTONE_URI, null)
            }
            manager.createNotificationChannel(callChannel)
        }
    }

    private fun showCallNotification(id: Int, title: String, body: String, payload: String?) {
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
            Notification.Builder(this, callNotificationChannelId)
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
            .setFullScreenIntent(pendingIntent, true)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .build()
        manager.notify(id, notification)
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

private fun Cursor.getStringOrNullCompat(columnName: String): String? {
    val index = getColumnIndex(columnName)
    if (index < 0 || isNull(index)) return null
    return getString(index)
}
