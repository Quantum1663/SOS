import 'dart:async';

class TriggerController {
  int _tapCount = 0;
  Timer? _timer;

  void registerTap({
    required Function onSingle,
    required Function onDouble,
    required Function onTriple,
  }) {
    _tapCount++;

    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () {
      if (_tapCount == 1) {
        onSingle();
      } else if (_tapCount == 2) {
        onDouble();
      } else if (_tapCount >= 3) {
        onTriple();
      }
      _tapCount = 0;
    });
  }
}