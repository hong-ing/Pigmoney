import 'package:flutter_riverpod/flutter_riverpod.dart';

// 동기화 로딩 상태를 관리하는 Provider
final syncLoadingProvider = StateNotifierProvider<SyncLoadingNotifier, SyncLoadingState>((ref) {
  return SyncLoadingNotifier();
});

class SyncLoadingState {
  final bool isLoading;
  final String? message;
  final double? progress;

  SyncLoadingState({
    this.isLoading = false,
    this.message,
    this.progress,
  });

  SyncLoadingState copyWith({
    bool? isLoading,
    String? message,
    double? progress,
  }) {
    return SyncLoadingState(
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
      progress: progress ?? this.progress,
    );
  }
}

class SyncLoadingNotifier extends StateNotifier<SyncLoadingState> {
  SyncLoadingNotifier() : super(SyncLoadingState());

  void startLoading({String? message}) {
    state = state.copyWith(
      isLoading: true,
      message: message ?? '데이터 동기화 중...',
      progress: null,
    );
  }

  void updateProgress(double progress, {String? message}) {
    if (state.isLoading) {
      state = state.copyWith(
        progress: progress,
        message: message,
      );
    }
  }

  void updateMessage(String message) {
    if (state.isLoading) {
      state = state.copyWith(message: message);
    }
  }

  void stopLoading() {
    state = SyncLoadingState();
  }

  bool get isLoading => state.isLoading;
}