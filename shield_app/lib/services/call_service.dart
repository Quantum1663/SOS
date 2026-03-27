import 'package:flutter/services.dart';

class CallService {
  static const MethodChannel _channel =
      MethodChannel('shield.emergency.call');

  static Future<void> callEmergency(String number) async {
    try {
      await _channel.invokeMethod('callEmergency', {
        'number': number,
      });
    } catch (e) {
      throw Exception('Call failed: $e');
    }
  }
}
