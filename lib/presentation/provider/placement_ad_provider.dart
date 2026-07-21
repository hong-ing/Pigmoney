import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tnk_flutter_rwd/tnk_flutter_rwd.dart';

import '../../core/utils/log/logger.dart';
import '../shopping/model/placement_ad_model.dart';
import 'user_provider.dart';

// PlacementAdState 클래스 정의
class PlacementAdState {
  final List<TnkPlacementAdItem> adList;
  final PlacementPubInfo pubInfo;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;

  PlacementAdState({
    this.adList = const [],
    PlacementPubInfo? pubInfo,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
  }) : pubInfo = pubInfo ?? PlacementPubInfo();

  PlacementAdState copyWith({
    List<TnkPlacementAdItem>? adList,
    PlacementPubInfo? pubInfo,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
  }) {
    return PlacementAdState(
      adList: adList ?? this.adList,
      pubInfo: pubInfo ?? this.pubInfo,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// PlacementAdNotifier 클래스 정의
class PlacementAdNotifier extends StateNotifier<PlacementAdState> {
  final _tnkFlutterRwdPlugin = TnkFlutterRwd();
  final Ref ref;

  PlacementAdNotifier(this.ref) : super(PlacementAdState()) {
    // Provider 생성 시 자동으로 광고 로드
    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    try {
      // TNK 사용자 설정
      final userRepository = ref.read(userRepositoryProvider);
      final user = await userRepository.getCurrentUser();
      if (user != null) {
        await _tnkFlutterRwdPlugin.setUserName(user.uid);
        await _tnkFlutterRwdPlugin.setCOPPA(false);
        _tnkFlutterRwdPlugin.setUseTermsPopup(false);
      }
    } catch (e) {
      logger.e('TNK 초기화 중 오류: $e');
    }
    
    // 광고 로드
    loadPlacementAds();
  }

  Future<void> loadPlacementAds() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, hasError: false, errorMessage: null);

    try {
      // 플레이스먼트 광고 데이터 가져오기
      String? placementData = await _tnkFlutterRwdPlugin.getPlacementJsonData(
        state.pubInfo.plcmt_id,
      );

      if (placementData != null) {
        Map<String, dynamic> jsonObject = jsonDecode(placementData);
        String resCode = jsonObject["res_code"];

        if (resCode == "1") {
          List<TnkPlacementAdItem> loadedAds = parseJsonToTnkPlacementAdItem(
            jsonObject["ad_list"],
          );

          // pub_info 업데이트
          PlacementPubInfo newPubInfo = state.pubInfo;
          if (jsonObject.containsKey("pub_info")) {
            Map<String, dynamic> pubInfoMap = jsonObject["pub_info"];
            newPubInfo = PlacementPubInfo.fromJson(pubInfoMap);
          }

          state = state.copyWith(
            adList: loadedAds,
            pubInfo: newPubInfo,
            isLoading: false,
          );

          logger.d('플레이스먼트 광고 로드 성공: ${loadedAds.length}개');
        } else {
          throw Exception('광고 로드 실패: ${jsonObject["res_message"]}');
        }
      }
    } catch (e) {
      logger.e('플레이스먼트 광고 로드 중 오류: $e');
      state = state.copyWith(
        hasError: true,
        errorMessage: e.toString(),
        isLoading: false,
      );
    }
  }

  void refreshAds() {
    loadPlacementAds();
  }
}

// Provider 정의
final placementAdProvider = StateNotifierProvider<PlacementAdNotifier, PlacementAdState>((ref) {
  return PlacementAdNotifier(ref);
});