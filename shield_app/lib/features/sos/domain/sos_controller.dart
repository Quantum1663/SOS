import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sos_state.dart';

final sosControllerProvider =
    StateNotifierProvider<SosController, SosStatus>(
  (ref) => SosController(),
);

class SosController extends StateNotifier<SosStatus> {
  SosController() : super(SosStatus.idle);

  void activate() {
    state = SosStatus.activating;
  }

  void confirmActive() {
    state = SosStatus.active;
  }

  void reset() {
    state = SosStatus.idle;
  }
}
