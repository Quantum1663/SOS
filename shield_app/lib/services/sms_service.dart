import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SmsService {
  static const MethodChannel _channel =
      MethodChannel('shield.emergency.sms');

  static bool get supportsSilentSend =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> sendSOS({
    required String number,
    required String message,
  }) async {
    if (!supportsSilentSend) {
      throw UnsupportedError(
        'Silent SOS messaging is currently supported only on Android.',
      );
    }

    try {
      await _channel.invokeMethod('sendSOS', {
        'number': number,
        'message': message,
      });
    } catch (e) {
      throw Exception('SMS failed: $e');
    }
  }
}
