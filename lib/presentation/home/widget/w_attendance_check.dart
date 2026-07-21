import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:pigmoney/core/utils/log/logger.dart';
import 'package:pigmoney/data/attendance/attendance_manager.dart';
import 'package:pigmoney/data/attendance/model/attendance_model.dart';
import 'package:pigmoney/presentation/provider/ad_cooldown_provider.dart';
import 'package:pigmoney/presentation/provider/attendance_provider.dart';
import 'package:pigmoney/presentation/provider/user_provider.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../../core/ads/admob_service_attendance_check.dart';
import '../../provider/settings_provider.dart';

class AttendanceCheckWidget extends ConsumerStatefulWidget {
  const AttendanceCheckWidget({super.key});

  @override
  ConsumerState<AttendanceCheckWidget> createState() => _AttendanceCheckWidgetState();
}

class _AttendanceCheckWidgetState extends ConsumerState<AttendanceCheckWidget> {
  // 매니저 참조를 위한 변수
  // AttendanceManager? _cachedManager;

  // 애니메이션 상태 관리
  final Map<int, bool> _animatingSlots = {};
  final Map<int, bool> _showReward = {};

  // ✅ 각 슬롯별 처리 상태 추가
  final Map<int, bool> _slotProcessing = {};

  // 슬롯 탭 처리 중인지 여부
  bool _isProcessingTap = false;

  // ALL 슬롯 광고 처리 중인지 여부 (별도 관리)
  bool _isProcessingAllSlotAd = false;

  // ✅ 보상 처리 완료 여부 추적 (Race Condition 방지)
  final Map<int, bool> _rewardProcessingComplete = {};

  // ✅ 리프레시 상태 추가
  bool _isRefreshing = false;

  // 애니메이션 시간 상수
  static const int animationDuration = 750; // 1500ms에서 750ms로 절반 감소

  final AudioPlayer _attendanceSoundPlayer = AudioPlayer();
  bool _isSoundPlaying = false;

  @override
  void initState() {
    super.initState();

    _configureAttendanceSound();
  }

  @override
  void dispose() {
    // ✅ 모든 상태 클리어
    _animatingSlots.clear();
    _showReward.clear();
    _slotProcessing.clear();
    _rewardProcessingComplete.clear();
    _isProcessingTap = false;
    _isProcessingAllSlotAd = false;
    _isRefreshing = false;

    _safeDisposeAttendanceSound();
    super.dispose();
  }

  Future<void> _configureAttendanceSound() async {
    try {
      await _attendanceSoundPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      print('출석체크 오디오 설정 오류: $e');
    }
  }

  void _safeDisposeAttendanceSound() {
    try {
      if (_attendanceSoundPlayer.state != PlayerState.disposed) {
        _attendanceSoundPlayer.stop();
        _attendanceSoundPlayer.dispose();
      }
    } catch (e) {
      print('출석체크 오디오 dispose 오류: $e');
    }
  }

  Future<void> _playAttendanceSound() async {
    if (_isSoundPlaying) return;

    try {
      // 설정에서 사운드가 활성화되어 있는지 확인
      final settings = ref.read(settingsProvider);
      if (!settings.isSfxEnabled) return;

      _isSoundPlaying = true;
      await _attendanceSoundPlayer.play(AssetSource('audio/coin_attendance_sound.mp3'));

      // 재생이 끝나면 플래그 해제
      _attendanceSoundPlayer.onPlayerComplete.first.then((_) {
        if (mounted) {
          _isSoundPlaying = false;
        }
      });
    } catch (e) {
      print('출석체크 효과음 재생 오류: $e');
      _isSoundPlaying = false;
    }
  }

  Future<void> _applyVibration() async {
    final settings = ref.read(settingsProvider);
    if (!settings.isVibrationEnabled) return;

    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100, amplitude: 150);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firebase Auth 상태 체크
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    if (!isLoggedIn) {
      return Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(horizontal: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: const Center(
            child: Text(
              '로그인이 필요합니다',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // ✅ AsyncValue를 처리하도록 수정
    final managerAsync = ref.watch(attendanceManagerProvider);

    return managerAsync.when(
      data: (manager) {
        // 매니저가 null인 경우
        if (manager == null) {
          return _buildLoadingContainer();
        }

        final slots = manager.slots;

        // 슬롯 개수 검증 (이제는 거의 발생하지 않을 것임)
        if (slots.length != 3) {
          logger.e('출석체크 슬롯 개수 오류: ${slots.length}개 (3개여야 함)');
          // 매니저 강제 리프레시
          Future.microtask(() async {
            if (mounted) {
              await manager.forceRefresh();
            }
          });
          return _buildLoadingContainer();
        }

        return Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            children: [
              _buildTitle(manager),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(slots.length, (index) => _buildAttendanceSlot(slots[index], index, manager)),
              ).pSymmetric(h: 15, v: 5),
              // 배너 텍스트가 없을 때만 ALL 출석 문구 표시
            ],
          ),
        );
      },
      loading: () => _buildLoadingContainer(),
      error: (error, stack) {
        logger.e('출석체크 매니저 로딩 오류: $error');
        return Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('출석체크 로딩 중 오류 발생', style: TextStyle(fontSize: 16, color: Colors.red)),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(attendanceManagerProvider),
                    child: Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8E7),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildTitle(AttendanceManager manager) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFB6C1),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          (manager.showAllClearCelebration == true ? '🎉축하드려요! 오늘의 출첵보상 모두 완료!🎉' : '🎁출석체크 행운의 동전뽑기🎁').text.black.bold
              .letterSpacing(-0.3)
              .center
              .size(15)
              .make(),

          // 우측 리프레시 버튼
          if (!manager.showAllClearCelebration)
            Positioned(
              right: 8,
              child: InkWell(
                onTap: _isRefreshing ? null : _handleRefresh, // 리프레시 중이면 비활성화
                child: _isRefreshing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                        ),
                      ).p(5)
                    : Image.asset('assets/icons/ic_refresh.png', width: 25, height: 25).p(5),
              ).material(color: Colors.transparent).clipOval(),
            ),
        ],
      ),
    );
  }

  /// ✅ 리프레시 버튼 핸들러 - 서버에서 최신 데이터 가져오기
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      // 로컬 상태 초기화 - 애니메이션 및 보상 표시 상태 초기화
      _animatingSlots.clear();
      _showReward.clear();
      _slotProcessing.clear();
    });

    try {
      print('출석체크 서버 리프레시 시작');

      // ✅ 현재 매니저가 있으면 먼저 forceRefresh 호출
      final managerAsync = ref.read(attendanceManagerProvider);
      if (managerAsync.hasValue && managerAsync.value != null) {
        final manager = managerAsync.value!;
        // 매니저가 dispose되지 않았는지 확인
        if (!manager.isDisposed) {
          await manager.forceRefresh();
        }
      }

      // ✅ provider를 invalidate하여 완전히 새로 생성
      ref.invalidate(attendanceManagerProvider);

      // ✅ 사용자 데이터도 새로고침
      await ref.read(currentUserProvider.notifier).refreshUserData();

      // ✅ 새로운 매니저가 완전히 로드될 때까지 대기
      final newManager = await ref.read(attendanceManagerProvider.future);

      // ✅ 새 매니저가 null이 아니고 초기화가 완료되었는지 확인
      if (newManager != null && newManager.isInitialised) {
        print('출석체크 서버 리프레시 성공');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('출석체크가 새로고침 되었습니다.'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }

      print('출석체크 서버 리프레시 완료');
    } catch (e) {
      print('출석체크 리프레시 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('출석체크 새로고침 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // UI가 업데이트될 시간을 주기 위해 약간의 딜레이
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Widget _buildAttendanceSlot(AttendanceSlotData slot, int index, AttendanceManager manager) {
    // ✅ 개별 슬롯의 처리 상태도 확인
    final isTappable =
        (slot.status == AttendanceStatus.active || slot.status == AttendanceStatus.allCompleted) &&
        !_isProcessingTap &&
        !_isProcessingAllSlotAd &&
        !(_slotProcessing[index] ?? false); // 슬롯별 처리 상태 확인

    return InkWell(
      onTap: isTappable ? () => _handleTap(slot, index, manager) : null,
      borderRadius: BorderRadius.circular(12),
      child: _buildSlotCircle(slot, index),
    ).expand();
  }

  Future<void> _handleTap(AttendanceSlotData slot, int index, AttendanceManager manager) async {
    // ✅ 슬롯별 중복 처리 방지
    if (_isProcessingTap || _isProcessingAllSlotAd || (_slotProcessing[index] ?? false)) {
      logger.d('이미 처리 중인 탭입니다. index: $index');
      return;
    }

    // ✅ 현재 상태 재확인
    if (slot.status != AttendanceStatus.active && slot.status != AttendanceStatus.allCompleted) {
      logger.d('슬롯이 활성 상태가 아닙니다. status: ${slot.status}');
      return;
    }

    try {
      if (slot.status == AttendanceStatus.allCompleted) {
        // ✅ 광고 쿨다운 체크
        final cooldownNotifier = ref.read(adCooldownProvider);
        const adKey = 'attendance_all_ad';

        if (!cooldownNotifier.canShowAd(adKey)) {
          final remaining = cooldownNotifier.getRemainingSeconds(adKey);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('잠시 후 다시 시도해주세요. 남은시간 ${remaining}초'),
                backgroundColor: Colors.orange[700],
                duration: Duration(seconds: 1),
              ),
            );
          }
          return;
        }

        // 쿨다운 기록
        cooldownNotifier.recordAdAttempt(adKey);

        _playAttendanceSound();
        _applyVibration();
        // ALL 슬롯 처리 - 별도 플래그 사용
        setState(() {
          _isProcessingAllSlotAd = true;
          _slotProcessing[index] = true;
          _rewardProcessingComplete[index] = false; // ✅ 보상 처리 시작 표시
        });

        // ✅ 새 흐름: 리워드 광고 없이 애니메이션 + 머니 먼저 보여주고, 그 후 전면 광고 노출
        try {
          logger.d('ALL 슬롯 보상 처리 시작 (광고 선노출 없음)');

          // ✅ 매니저가 이미 dispose된 경우(리프레시/재시작 타이밍): 보상을 지급할 수 없으므로
          // 가짜 성공 UI/전면광고 없이 상태만 정리하고 중단
          if (manager.isDisposed) {
            logger.w('ALL 슬롯: manager가 이미 dispose됨 → 보상 처리 중단');
            if (mounted) {
              setState(() {
                _isProcessingAllSlotAd = false;
                _slotProcessing[index] = false;
                _rewardProcessingComplete[index] = false;
              });
            }
            return;
          }

          // ✅ 1. 먼저 서버에 보상 저장 (애니메이션보다 먼저!)
          await manager.onAllClearAdWatched();
          logger.d('ALL 슬롯 서버 저장 완료');

          // ✅ 2. 서버 저장 완료 후 보상 처리 완료 표시
          _rewardProcessingComplete[index] = true;

          // 3. 동전 애니메이션 시작
          if (mounted) {
            setState(() {
              _animatingSlots[index] = true;
              _showReward[index] = false;
            });
          }

          // 4. 애니메이션 완료까지 대기
          await Future.delayed(Duration(milliseconds: animationDuration));

          // ✅ 5. 서버 저장이 이미 완료되었으므로 안전하게 새로고침
          if (!manager.isDisposed && mounted) {
            await manager.forceRefresh();
            await ref.read(currentUserProvider.notifier).refreshUserData();
          }

          // 6. 애니메이션 종료 상태로 변경 (획득 머니 표시)
          if (mounted) {
            setState(() {
              _animatingSlots[index] = false;
              _showReward[index] = true;
              _isProcessingAllSlotAd = false;
              _slotProcessing[index] = false;
            });
          }

          // 7. 머니가 화면에 뜬 뒤 잠깐 보여주고 전면 광고 노출
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) {
            admobService4.loadAndShowInterstitialAdWithFallback();
            logger.d('ALL 슬롯 보상 처리 완료 + 전면 광고 요청');
          }
        } catch (e) {
          logger.e('ALL 슬롯 보상 처리 오류: $e');
          _rewardProcessingComplete[index] = false; // ✅ 실패 시에도 표시
          if (mounted) {
            setState(() {
              _isProcessingAllSlotAd = false;
              _slotProcessing[index] = false;
              _animatingSlots[index] = false;
              _showReward[index] = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('보상 처리 중 오류가 발생했습니다: $e')),
            );
          }
        }
      } else if (slot.status == AttendanceStatus.active) {
        // 일반 슬롯 처리 (아침, 저녁)
        setState(() {
          _isProcessingTap = true;
          _slotProcessing[index] = true;
        });

        _playAttendanceSound();
        _applyVibration();

        // 1. 애니메이션 시작
        setState(() {
          _animatingSlots[index] = true;
          _showReward[index] = false;
        });

        // 2. 애니메이션과 서버 업데이트를 병렬로 처리
        final animationFuture = Future.delayed(Duration(milliseconds: animationDuration));
        final serverFuture = manager.onSlotTapped(index);

        // 모든 작업이 완료될 때까지 대기
        await Future.wait([animationFuture, serverFuture]);

        // 3. 매니저 상태 강제 리프레시
        if (!manager.isDisposed && mounted) {
          // ✅ 서버에서 최신 데이터 강제 새로고침
          await manager.forceRefresh();

          // ✅ 사용자 데이터도 리프레시
          await ref.read(currentUserProvider.notifier).refreshUserData();
        }

        // 4. 애니메이션 종료 상태로 변경 (실제 서버 값으로 표시)
        if (mounted) {
          setState(() {
            _animatingSlots[index] = false;
            _showReward[index] = true;
            _isProcessingTap = false;
            _slotProcessing[index] = false;
          });
        }
      }
    } catch (e) {
      logger.e('출석체크 탭 처리 오류: $e');
      if (mounted) {
        setState(() {
          _isProcessingTap = false;
          _isProcessingAllSlotAd = false;
          _slotProcessing[index] = false;
          _animatingSlots[index] = false;
          _showReward[index] = false;
        });

        // ✅ 오류 발생 시 사용자에게 알림
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('출석체크 처리 중 오류가 발생했습니다. 다시 시도해주세요. $e')),
        );
      }
    }
  }

  Widget _buildSlotCircle(AttendanceSlotData slot, int index) {
    // 그 외 상태는 기존과 동일하게 DottedBorder 적용
    return Stack(
      alignment: Alignment.center,
      children: [
        if (slot.status == AttendanceStatus.completed || slot.status == AttendanceStatus.allCompleted) ...{
          if (slot.status == AttendanceStatus.allCompleted) Image.asset('assets/icons/ic_attendance_all.png', width: 80, height: 80),
        } else ...{
          if (slot.status != AttendanceStatus.active) Image.asset('assets/icons/ic_dot_border.png', width: 80, height: 80),
        },
        SizedBox(
          width: 100,
          height: 100,
          child: Center(child: _buildCircleContent(slot, index)),
        ),
      ],
    );
  }

  Widget _buildCircleContent(AttendanceSlotData slot, int index) {
    // ✅ 처리 중인 경우 애니메이션 우선 표시
    if (_animatingSlots[index] == true || _slotProcessing[index] == true) {
      return TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Duration(milliseconds: animationDuration),
        builder: (context, value, child) {
          // 애니메이션 단계에 따라 다르게 처리
          // 0-0.7: 팽이처럼 돌기
          // 0.7-0.9: 위로 튕기기
          // 0.9-1.0: 다시 내려오기

          double yOffset = 0;
          if (value < 0.7) {
            // 팽이처럼 돌기만 하는 단계
            yOffset = 0;
          } else if (value < 0.9) {
            // 위로 튕기는 단계 (0.7~0.9 구간에서 위로 올라감)
            yOffset = -30 * ((value - 0.7) / 0.2);
          } else {
            // 다시 내려오는 단계 (0.9~1.0 구간에서 다시 내려옴)
            yOffset = -30 * (1 - ((value - 0.9) / 0.1));
          }

          return Transform.translate(
            offset: Offset(0, yOffset),
            child: Transform.rotate(
              // y축 기준으로 회전 (팽이처럼 돌아가는 효과)
              alignment: Alignment.center,
              angle: value * 10 * math.pi, // 빠르게 여러 바퀴 회전
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // 원근감 추가
                  ..rotateY(value * 15 * math.pi), // y축 기준 회전
                child: Image.asset(
                  // 모든 슬롯 동일하게 코인 타입별 이미지 사용
                  slot.coinType.assetPath,
                  width: 80,
                ),
              ),
            ),
          );
        },
      );
    }

    // ✅ 완료 상태 표시 (서버 상태 기반)
    if (slot.status == AttendanceStatus.completed || _showReward[index] == true) {
      // 모든 슬롯 동일하게 처리 (ALL 슬롯도 코인 타입별 이미지 사용)
      return Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(slot.coinType.assetPath),
          Text(
            '${slot.reward}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.black,
            ),
          ),
          // 2) 내부를 채우는 Text
          Text(
            '${slot.reward}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    // ✅ 나머지 상태들
    switch (slot.status) {
      case AttendanceStatus.pending:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            slot.timeName.text
                .size(slot.timeName == '완벽출석' ? 14 : 16)
                .letterSpacing(-0.2)
                .heightRelaxed
                .bold
                .color(Colors.grey[500])
                .make(),
            slot.timeRangeLabel.text
                .size(slot.timeRangeLabel == '한번더!' ? 16 : 14)
                .letterSpacing(-0.2)
                .bold
                .heightRelaxed
                .color(Colors.grey[500])
                .make(),
          ],
        );

      case AttendanceStatus.active:
        return Image.asset(slot.coinType.assetPath, width: 80);

      case AttendanceStatus.missed:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            slot.timeName.text.size(14).letterSpacing(-0.2).bold.color(Colors.grey[500]).make(),
            slot.timeRangeLabel.text.size(14).letterSpacing(-0.2).bold.heightRelaxed.color(Colors.grey[500]).make(),
          ],
        );

      case AttendanceStatus.allCompleted:
        return Image.asset('assets/icons/ic_random_coin.png', width: 80);

      default:
        return Container();
    }
  }
}
