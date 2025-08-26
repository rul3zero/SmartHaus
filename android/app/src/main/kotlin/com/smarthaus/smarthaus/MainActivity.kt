package com.smarthaus.smarthaus

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "smarthaus/notifications"
    private val SECURITY_CHANNEL_ID = "security_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        createNotificationChannel()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Security Alert"
                    val body = call.argument<String>("body") ?: "Security event detected"
                    val sound = call.argument<Boolean>("sound") ?: true
                    val vibrate = call.argument<Boolean>("vibrate") ?: true
                    
                    showNotification(title, body, sound, vibrate)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Security Alerts"
            val descriptionText = "High priority security notifications"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(SECURITY_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableVibration(true)
                enableLights(true)
                setShowBadge(true)
            }
            
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showNotification(title: String, body: String, sound: Boolean, vibrate: Boolean) {
        val builder = NotificationCompat.Builder(this, SECURITY_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)

        var defaults = 0
        if (sound) {
            defaults = defaults or NotificationCompat.DEFAULT_SOUND
        }
        
        if (vibrate) {
            defaults = defaults or NotificationCompat.DEFAULT_VIBRATE
        }
        
        if (defaults != 0) {
            builder.setDefaults(defaults)
        }

        with(NotificationManagerCompat.from(this)) {
            if (areNotificationsEnabled()) {
                notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
            }
        }
    }
}
