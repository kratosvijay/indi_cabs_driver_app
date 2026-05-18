import 'dart:async';
import 'package:flutter/foundation.dart';

class WaitingTimerService {
  static final WaitingTimerService _instance = WaitingTimerService._internal();
  factory WaitingTimerService() => _instance;
  WaitingTimerService._internal();

  Timer? _timer;
  int _waitingSeconds = 0;
  bool _isActive = false;

  final _waitingSecondsController = StreamController<int>.broadcast();
  Stream<int> get waitingSecondsStream => _waitingSecondsController.stream;

  void startWaiting() {
    if (_isActive) return;
    _isActive = true;
    debugPrint("WaitingTimerService: Starting manual waiting timer");
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _waitingSeconds++;
      _waitingSecondsController.add(_waitingSeconds);
    });
  }

  void stopWaiting() {
    _isActive = false;
    _timer?.cancel();
    debugPrint("WaitingTimerService: Stopped manual waiting timer. Total seconds: $_waitingSeconds");
  }

  void reset() {
    stopWaiting();
    _waitingSeconds = 0;
  }

  int get currentWaitingMinutes => (_waitingSeconds / 60).ceil();
  int get currentWaitingSeconds => _waitingSeconds;
}
