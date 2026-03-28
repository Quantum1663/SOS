package com.example.shield_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
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
    private val notificationId = 1120
    private val shortcutScheme = "shield"
    private val shortcutHost = "shortcut"

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
        latestShortcutAction = extractShortcutAction(intent) ?: latestShortcutAction
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
                    "disablePersistentShortcuts" -> {
                        disablePersistentShortcuts()
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
        extractShortcutAction(intent)?.let { action ->
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

    private fun showPersistentShortcutNotification() {
        createNotificationChannelIfNeeded()

        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SHIELD Quick Access")
            .setContentText("Tap to open. Use actions for panic, silent SOS, or a 15 min safety check.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Tap to open SHIELD fast. Use Full Panic for 112 + alerts, Silent SOS for discreet escalation, or 15 min Check-in before late travel."
                )
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(createActivityPendingIntent(null))
            .addAction(
                0,
                "Full Panic",
                createActivityPendingIntent("full_panic")
            )
            .addAction(
                0,
                "Silent SOS",
                createActivityPendingIntent("silent_sos")
            )
            .addAction(
                0,
                "15 min Check-in",
                createActivityPendingIntent("check_in")
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
            "SHIELD Quick Access",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Fast emergency actions for SHIELD"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun createActivityPendingIntent(action: String?): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK
            if (action != null) {
                data = Uri.parse("$shortcutScheme://$shortcutHost/$action")
            }
        }

        return PendingIntent.getActivity(
            this,
            action?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun extractShortcutAction(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != shortcutScheme || data.host != shortcutHost) {
            return null
        }

        return when (data.lastPathSegment) {
            "full_panic" -> "full_panic"
            "silent_sos" -> "silent_sos"
            "check_in" -> "check_in"
            else -> null
        }
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
