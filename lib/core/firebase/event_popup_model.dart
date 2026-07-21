// event_popup_model.dart
// 이벤트 팝업 데이터 모델
// 2025-07-29

/// 이벤트 팝업 데이터를 담는 모델 클래스
class EventPopupModel {
  final bool enabled;
  final String startDate;
  final String endDate;
  final String title;
  final String message;
  final String minBuildNumber;
  final String eventId;
  final String linkUrl;
  final String linkTitle;

  const EventPopupModel({
    required this.enabled,
    required this.startDate,
    required this.endDate,
    required this.title,
    required this.message,
    required this.minBuildNumber,
    required this.eventId,
    required this.linkUrl,
    required this.linkTitle,
  });

  /// Remote Config 데이터에서 EventPopupModel 생성
  factory EventPopupModel.fromRemoteConfig({
    required bool enabled,
    required String startDate,
    required String endDate,
    required String title,
    required String message,
    required String minBuildNumber,
    required String eventId,
    required String linkUrl,
    required String linkTitle,
  }) {
    return EventPopupModel(
      enabled: enabled,
      startDate: startDate,
      endDate: endDate,
      title: title,
      message: message,
      minBuildNumber: minBuildNumber,
      eventId: eventId,
      linkUrl: linkUrl,
      linkTitle: linkTitle,
    );
  }

  /// 빈 모델 (기본값)
  factory EventPopupModel.empty() {
    return const EventPopupModel(
      enabled: false,
      startDate: '',
      endDate: '',
      title: '',
      message: '',
      minBuildNumber: '0',
      eventId: '',
      linkUrl: '',
      linkTitle: '',
    );
  }

  /// 팝업이 유효한지 체크 (기본 조건)
  bool get isValid => enabled && startDate.isNotEmpty && title.isNotEmpty && eventId.isNotEmpty;

  /// 링크가 있는지 확인
  bool get hasLink => linkUrl.isNotEmpty && linkTitle.isNotEmpty;

  /// 이벤트 기간이 하루짜리인지 확인
  bool get isSingleDay => endDate.isEmpty || startDate == endDate;

  /// 이벤트 기간 문자열 반환 (예: "2025-07-29" 또는 "2025-07-29 ~ 2025-07-31")
  String get periodString {
    if (isSingleDay) {
      return startDate;
    }
    return '$startDate ~ $endDate';
  }

  @override
  String toString() {
    return 'EventPopupModel(enabled: $enabled, eventId: $eventId, startDate: $startDate, endDate: $endDate, title: $title, message: $message, minBuildNumber: $minBuildNumber, linkUrl: $linkUrl, linkTitle: $linkTitle)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventPopupModel &&
        other.enabled == enabled &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.title == title &&
        other.message == message &&
        other.minBuildNumber == minBuildNumber &&
        other.eventId == eventId &&
        other.linkUrl == linkUrl &&
        other.linkTitle == linkTitle;
  }

  @override
  int get hashCode {
    return enabled.hashCode ^
        startDate.hashCode ^
        endDate.hashCode ^
        title.hashCode ^
        message.hashCode ^
        minBuildNumber.hashCode ^
        eventId.hashCode ^
        linkUrl.hashCode ^
        linkTitle.hashCode;
  }

  EventPopupModel copyWith({
    bool? enabled,
    String? startDate,
    String? endDate,
    String? title,
    String? message,
    String? minBuildNumber,
    String? eventId,
    String? linkUrl,
    String? linkTitle,
  }) {
    return EventPopupModel(
      enabled: enabled ?? this.enabled,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      title: title ?? this.title,
      message: message ?? this.message,
      minBuildNumber: minBuildNumber ?? this.minBuildNumber,
      eventId: eventId ?? this.eventId,
      linkUrl: linkUrl ?? this.linkUrl,
      linkTitle: linkTitle ?? this.linkTitle,
    );
  }
}