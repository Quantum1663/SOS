package com.example.shield_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val callChannel = "shield.emergency.call"
    private val smsChannel = "shield.emergency.sms"
    private val callPermissionRequestCode = 1001
    private val smsPermissionRequestCode = 1002

    private var pendingCallNumber: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingSmsNumber: String? = null
    private var pendingSmsMessage: String? = null
    private var pendingSmsResult: MethodChannel.Result? = null

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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED

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
        }
    }
}
