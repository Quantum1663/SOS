import 'package:flutter/services.dart';

class SmsService {
  static const MethodChannel _channel =
      MethodChannel('shield.emergency.sms');

  static Future<void> sendSOS({
    required String number,
    required String message,
  }) async {
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
