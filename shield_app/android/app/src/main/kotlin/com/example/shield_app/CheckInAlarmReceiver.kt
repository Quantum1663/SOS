package com.example.shield_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class CheckInAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ensureNotificationChannel(context)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val openShieldIntent = ShortcutIntents.createActivityPendingIntent(
            context,
            ShortcutIntents.checkInExpired
        )

        val notification = NotificationCompat.Builder(context, checkInChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Get Home Safe expired")
            .setContentText("Tap to reopen SHIELD and alert your trusted circle if you are not safe.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Your Get Home Safe timer has expired. Tap to reopen SHIELD and continue with Alert Family if you still need help."
                )
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(openShieldIntent)
            .addAction(
                0,
                "Open SHIELD",
                openShieldIntent
            )
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            checkInChannelId,
            "SHIELD Get Home Safe",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts for expired Get Home Safe timers"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val checkInChannelId = "shield.check_in_expiry"
        private const val notificationId = 1121
    }
}
