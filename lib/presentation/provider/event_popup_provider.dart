// event_popup_provider.dart
// 이벤트 팝업 상태 관리 Provider
// 2025-07-29

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pigmoney/core/firebase/event_popup_model.dart';
import 'package:pigmoney/core/firebase/firebase_remote_config_service.dart';
import 'package:pigmoney/core/utils/log/logger.dart';

/// 이벤트 팝업 상태
enum EventPopupStatus {
  loading, // 로딩 중
  hidden, // 숨김 (조건 불만족)
  ready, // 표시 준비 완료
  dismissed, // 사용자가 닫음
  error, // 오류 발생
}

/// 이벤트 팝업 상태를 관리하는 클래스
class EventPopupState {
  final EventPopupStatus status;
  final EventPopupModel? popup;
  final String? errorMessage;

  const EventPopupState({
    required this.status,
    this.popup,
    this.errorMessage,
  });

  EventPopupState copyWith({
    EventPopupStatus? status,
    EventPopupModel? popup,
    String? errorMessage,
  }) {
    return EventPopupState(
      status: status ?? this.status,
      popup: popup ?? this.popup,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'EventPopupState(status: $status, popup: $popup, errorMessage: $errorMessage)';
  }
}

/// 이벤트 팝업 상태를 관리하는 Notifier
class EventPopupNotifier extends StateNotifier<EventPopupState> {
  EventPopupNotifier() : super(const EventPopupState(status: EventPopupStatus.loading)) {
    _initialize();
  }

  /// 초기화: Remote Config에서 데이터 가져와서 상태 업데이트
  Future<void> _initialize() async {
    try {
      logger.d('[EventPopup] 초기화 시작');

      // Remote Config 서비스 인스턴스 가져오기
      final remoteConfigService = await FirebaseRemoteConfigService.instance();

      // 이벤트 팝업 데이터 생성
      final popup = EventPopupModel.fromRemoteConfig(
        enabled: remoteConfigService.isEventEnabled,
        startDate: remoteConfigService.eventStartDate,
        endDate: remoteConfigService.eventEndDate,
        title: remoteConfigService.eventTitle,
        message: remoteConfigService.eventMessage,
        minBuildNumber: remoteConfigService.eventMinBuildNumber,
        eventId: remoteConfigService.eventId,
        linkUrl: remoteConfigService.eventLinkUrl,
        linkTitle: remoteConfigService.eventLinkTitle,
      );

      logger.d('[EventPopup] Remote Config 데이터: $popup');

      // 팝업 표시 조건 체크
      final shouldShow = await remoteConfigService.shouldShowEventPopup();

      if (shouldShow) {
        logger.i('[EventPopup] 팝업 표시 조건 만족');
        state = EventPopupState(
          status: EventPopupStatus.ready,
          popup: popup,
        );
      } else {
        logger.d('[EventPopup] 팝업 표시 조건 불만족');
        state = EventPopupState(
          status: EventPopupStatus.hidden,
          popup: popup,
        );
      }
    } catch (e) {
      logger.e('[EventPopup] 초기화 중 오류: $e');
      state = EventPopupState(
        status: EventPopupStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 팝업을 닫음 처리
  Future<void> dismissPopup() async {
    try {
      logger.d('[EventPopup] 팝업 닫기');

      state = state.copyWith(status: EventPopupStatus.dismissed);
    } catch (e) {
      logger.e('[EventPopup] 팝업 닫기 중 오류: $e');
    }
  }

  /// 팝업을 '다시 보지 않음' 처리
  Future<void> dismissPopupPermanently() async {
    try {
      logger.d('[EventPopup] 팝업 영구 닫기');

      final remoteConfigService = await FirebaseRemoteConfigService.instance();
      await remoteConfigService.dismissEventPopup();

      state = state.copyWith(status: EventPopupStatus.dismissed);

      logger.i('[EventPopup] 팝업 영구 닫기 완료');
    } catch (e) {
      logger.e('[EventPopup] 팝업 영구 닫기 중 오류: $e');
    }
  }

  /// 수동으로 상태 새로고침
  Future<void> refresh() async {
    state = const EventPopupState(status: EventPopupStatus.loading);
    await _initialize();
  }
}

/// 이벤트 팝업 Provider
final eventPopupProvider = StateNotifierProvider<EventPopupNotifier, EventPopupState>((ref) {
  return EventPopupNotifier();
});

/// 팝업이 표시 가능한지 여부를 반환하는 Provider
final shouldShowEventPopupProvider = Provider<bool>((ref) {
  final state = ref.watch(eventPopupProvider);
  return state.status == EventPopupStatus.ready && state.popup != null;
});

/// 현재 이벤트 팝업 데이터를 반환하는 Provider
final currentEventPopupProvider = Provider<EventPopupModel?>((ref) {
  final state = ref.watch(eventPopupProvider);
  return state.popup;
});
