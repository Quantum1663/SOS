import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class CallService {
  static const MethodChannel _channel =
      MethodChannel('shield.emergency.call');

  static Future<void> callEmergency(String number) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      final uri = Uri(scheme: 'tel', path: number);
      final launched = await launchUrl(uri);
      if (!launched) {
        throw Exception('Call failed: dialer could not be opened.');
      }
      return;
    }

    try {
      await _channel.invokeMethod('callEmergency', {
        'number': number,
      });
    } catch (e) {
      throw Exception('Call failed: $e');
    }
  }
}
