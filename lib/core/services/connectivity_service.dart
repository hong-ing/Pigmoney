import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityStatus {
  online,
  offline,
  checking,
}

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  ConnectivityStatus _status = ConnectivityStatus.checking;
  ConnectivityStatus? _previousStatus;
  
  ConnectivityStatus get status => _status;
  ConnectivityStatus? get previousStatus => _previousStatus;
  bool get isOnline => _status == ConnectivityStatus.online;
  bool get isOffline => _status == ConnectivityStatus.offline;
  bool get isChecking => _status == ConnectivityStatus.checking;
  
  // 오프라인에서 온라인으로 전환되었는지 확인
  bool get wasOfflineNowOnline => 
      _previousStatus == ConnectivityStatus.offline && 
      _status == ConnectivityStatus.online;

  ConnectivityService() {
    _initialize();
  }

  Future<void> _initialize() async {
    // 초기 연결 상태 확인
    await _checkConnectivity();
    
    // 연결 상태 변경 감지 리스너 등록
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
    } catch (e) {
      _status = ConnectivityStatus.offline;
      notifyListeners();
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    _previousStatus = _status;  // 이전 상태 저장
    
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      _status = ConnectivityStatus.offline;
    } else {
      _status = ConnectivityStatus.online;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// Provider
final connectivityServiceProvider = ChangeNotifierProvider<ConnectivityService>((ref) {
  return ConnectivityService();
});

// 연결 상태 Provider
final connectivityStatusProvider = Provider<ConnectivityStatus>((ref) {
  return ref.watch(connectivityServiceProvider).status;
});

// 온라인 상태 Provider
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).isOnline;
});