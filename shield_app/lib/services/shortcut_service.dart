import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ShortcutAction {
  quickOpen('quick_open'),
  fullPanic('full_panic'),
  silentSos('silent_sos'),
  checkIn('check_in'),
  checkInExpired('check_in_expired');

  const ShortcutAction(this.value);

  final String value;

  static ShortcutAction? fromValue(String? value) {
    for (final action in ShortcutAction.values) {
      if (action.value == value) {
        return action;
      }
    }
    return null;
  }
}

class ShortcutService {
  static const MethodChannel _channel =
      MethodChannel('shield.emergency.shortcuts');
  static final StreamController<ShortcutAction> _actions =
      StreamController<ShortcutAction>.broadcast();
  static bool _initialized = false;

  static bool get supportsPersistentShortcuts =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Stream<ShortcutAction> get actions => _actions.stream;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onShortcutAction') {
        return;
      }

      final action = ShortcutAction.fromValue(call.arguments as String?);
      if (action != null && !_actions.isClosed) {
        _actions.add(action);
      }
    });
  }

  static Future<void> enablePersistentShortcuts() async {
    if (!supportsPersistentShortcuts) {
      return;
    }

    await _channel.invokeMethod('enablePersistentShortcuts');
  }

  static Future<void> disablePersistentShortcuts() async {
    if (!supportsPersistentShortcuts) {
      return;
    }

    await _channel.invokeMethod('disablePersistentShortcuts');
  }

  static Future<void> setStealthMode(bool enabled) async {
    if (!supportsPersistentShortcuts) {
      return;
    }

    await _channel.invokeMethod(
      'setStealthMode',
      <String, Object>{'enabled': enabled},
    );
  }

  static Future<void> scheduleCheckInAlarm(DateTime deadline) async {
    if (!supportsPersistentShortcuts) {
      return;
    }

    await _channel.invokeMethod(
      'scheduleCheckInAlarm',
      <String, Object>{
        'deadlineEpochMillis': deadline.millisecondsSinceEpoch,
      },
    );
  }

  static Future<void> cancelCheckInAlarm() async {
    if (!supportsPersistentShortcuts) {
      return;
    }

    await _channel.invokeMethod('cancelCheckInAlarm');
  }

  static Future<ShortcutAction?> getInitialAction() async {
    if (!supportsPersistentShortcuts) {
      return null;
    }

    final result = await _channel.invokeMethod<String>('getInitialAction');
    return ShortcutAction.fromValue(result);
  }
}
