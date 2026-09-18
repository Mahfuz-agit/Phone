import 'package:flutter/foundation.dart';

class RefreshBus {
  RefreshBus._();
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void notify() => tick.value++;
}
