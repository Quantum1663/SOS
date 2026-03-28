package com.example.shield_app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val callChannel = "shield.emergency.call"
    private val smsChannel = "shield.emergency.sms"
    private val shortcutChannelName = "shield.emergency.shortcuts"

    private val callPermissionRequestCode = 1001
    private val smsPermissionRequestCode = 1002
    private val notificationPermissionRequestCode = 1003

    private val notificationChannelId = "shield.quick_access"
    private val checkInChannelId = "shield.check_in_expiry"
    private val preferencesName = "shield_prefs"
    private val stealthModeKey = "stealth_mode"
    private val notificationId = 1120
    private val checkInAlarmRequestCode = 1121
    private var pendingCallNumber: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingSmsNumber: String? = null
    private var pendingSmsMessage: String? = null
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    private var shortcutChannel: MethodChannel? = null
    private var latestShortcutAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        latestShortcutAction = ShortcutIntents.extractShortcutAction(intent) ?: latestShortcutAction
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "callEmergency") {
                    val number = call.argument<String>("number")

                    if (number != null) {
                        makePhoneCall(number, result)
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "sendSOS") {
                    val number = call.argument<String>("number")
                    val message = call.argument<String>("message")

                    if (number != null && message != null) {
                        sendSms(number, message, result)
                    } else {
                        result.error("INVALID_INPUT", "Number or message missing", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        shortcutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shortcutChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enablePersistentShortcuts" -> enablePersistentShortcuts(result)
                    "scheduleCheckInAlarm" -> {
                        val deadlineEpochMillis =
                            call.argument<Number>("deadlineEpochMillis")?.toLong()
                        if (deadlineEpochMillis == null) {
                            result.error(
                                "INVALID_DEADLINE",
                                "deadlineEpochMillis is required",
                                null
                            )
                        } else {
                            scheduleCheckInAlarm(deadlineEpochMillis)
                            result.success(null)
                        }
                    }
                    "cancelCheckInAlarm" -> {
                        cancelCheckInAlarm()
                        result.success(null)
                    }
                    "disablePersistentShortcuts" -> {
                        disablePersistentShortcuts()
                        result.success(null)
                    }
                    "setStealthMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setStealthMode(enabled)
                        result.success(null)
                    }

                    "getInitialAction" -> {
                        result.success(latestShortcutAction)
                        latestShortcutAction = null
                    }

                    else -> result.notImplemented()
                }
            }
        }

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShortcutIntents.extractShortcutAction(intent)?.let { action ->
            latestShortcutAction = action
            dispatchShortcutAction(action)
        }
    }

    private fun makePhoneCall(number: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CALL_PHONE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingCallNumber = number
            pendingCallResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE),
                callPermissionRequestCode
            )
            return
        }

        placePhoneCall(number, result)
    }

    private fun placePhoneCall(number: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_CALL).apply {
            data = Uri.parse("tel:$number")
        }

        try {
            startActivity(intent)
            result.success(null)
        } catch (exception: Exception) {
            result.error("CALL_FAILED", exception.localizedMessage, null)
        }
    }

    private fun sendSms(number: String, message: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.SEND_SMS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingSmsNumber = number
            pendingSmsMessage = message
            pendingSmsResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.SEND_SMS),
                smsPermissionRequestCode
            )
            return
        }

        try {
            val smsManager = SmsManager.getDefault()
            val parts = ArrayList(smsManager.divideMessage(message))
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(number, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(number, null, message, null, null)
            }
            result.success(null)
        } catch (exception: Exception) {
            result.error("SMS_FAILED", exception.localizedMessage, null)
        }
    }

    private fun enablePersistentShortcuts(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotificationResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode
            )
            return
        }

        showPersistentShortcutNotification()
        result.success(null)
    }

    private fun disablePersistentShortcuts() {
        NotificationManagerCompat.from(this).cancel(notificationId)
    }

    private fun setStealthMode(enabled: Boolean) {
        getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(stealthModeKey, enabled)
            .apply()
        showPersistentShortcutNotification()
    }

    private fun isStealthModeEnabled(): Boolean {
        return getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getBoolean(stealthModeKey, false)
    }

    private fun scheduleCheckInAlarm(deadlineEpochMillis: Long) {
        val alarmManager = getSystemService(AlarmManager::class.java)
        val pendingIntent = createCheckInAlarmPendingIntent()
        alarmManager.cancel(pendingIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                deadlineEpochMillis,
                pendingIntent
            )
            return
        }

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    deadlineEpochMillis,
                    pendingIntent
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT -> {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    deadlineEpochMillis,
                    pendingIntent
                )
            }
            else -> {
                alarmManager.set(
                    AlarmManager.RTC_WAKEUP,
                    deadlineEpochMillis,
                    pendingIntent
                )
            }
        }
    }

    private fun cancelCheckInAlarm() {
        val alarmManager = getSystemService(AlarmManager::class.java)
        alarmManager.cancel(createCheckInAlarmPendingIntent())
        NotificationManagerCompat.from(this).cancel(checkInAlarmRequestCode)
    }

    private fun createCheckInAlarmPendingIntent(): PendingIntent {
        val intent = Intent(this, CheckInAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            this,
            checkInAlarmRequestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun showPersistentShortcutNotification() {
        createNotificationChannelIfNeeded()
        val stealth = isStealthModeEnabled()

        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (stealth) "Daily Notes" else "SHIELD Travel Safety")
            .setContentText(
                if (stealth) {
                    "Tap to open your quick tools."
                } else {
                    "Tap to open. Use Full Panic, Alert Family, or Get Home Safe before late travel."
                }
            )
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    if (stealth) {
                        "Tap to open your quick tools. Open, Reach Home, and Check In stay ready from the notification shade."
                    } else {
                        "Tap to open SHIELD fast. Use Full Panic for 112 plus trusted-circle alerts, Alert Family for discreet escalation, or Get Home Safe before late travel."
                    }
                )
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(ShortcutIntents.createActivityPendingIntent(this, null))
            .addAction(
                0,
                if (stealth) "Call" else "Full Panic",
                ShortcutIntents.createActivityPendingIntent(this, ShortcutIntents.fullPanic)
            )
            .addAction(
                0,
                if (stealth) "Alert" else "Alert Family",
                ShortcutIntents.createActivityPendingIntent(this, ShortcutIntents.silentSos)
            )
            .addAction(
                0,
                if (stealth) "Reach Home" else "Get Home Safe",
                ShortcutIntents.createActivityPendingIntent(this, ShortcutIntents.checkIn)
            )
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            notificationChannelId,
            if (isStealthModeEnabled()) "Daily Notes" else "SHIELD Travel Safety",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = if (isStealthModeEnabled()) {
                "Quick tools for daily notes"
            } else {
                "Fast late-travel and emergency actions for SHIELD"
            }
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
        val checkInChannel = NotificationChannel(
            checkInChannelId,
            "SHIELD Get Home Safe",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts for expired Get Home Safe timers"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(checkInChannel)
    }

    private fun dispatchShortcutAction(action: String) {
        shortcutChannel?.invokeMethod("onShortcutAction", action)
        latestShortcutAction = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        when (requestCode) {
            callPermissionRequestCode -> {
                val number = pendingCallNumber
                val result = pendingCallResult
                pendingCallNumber = null
                pendingCallResult = null

                if (!granted || number == null || result == null) {
                    result?.error("CALL_PERMISSION_DENIED", "Call permission was denied", null)
                    return
                }

                placePhoneCall(number, result)
            }

            smsPermissionRequestCode -> {
                val number = pendingSmsNumber
                val message = pendingSmsMessage
                val result = pendingSmsResult
                pendingSmsNumber = null
                pendingSmsMessage = null
                pendingSmsResult = null

                if (!granted || number == null || message == null || result == null) {
                    result?.error("SMS_PERMISSION_DENIED", "SMS permission was denied", null)
                    return
                }

                sendSms(number, message, result)
            }

            notificationPermissionRequestCode -> {
                val result = pendingNotificationResult
                pendingNotificationResult = null

                if (!granted || result == null) {
                    result?.error(
                        "NOTIFICATION_PERMISSION_DENIED",
                        "Notification permission was denied",
                        null
                    )
                    return
                }

                showPersistentShortcutNotification()
                result.success(null)
            }
        }
    }
}
