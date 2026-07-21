import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sim_card_code/sim_card_code.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/services/deep_link_service.dart';
import '../../core/utils/advertising_id_helper.dart';
import '../../core/utils/device_id_helper.dart';
import '../../data/login/apple_auth_repository.dart';
import '../../data/login/google_auth_repository.dart';
import '../../data/login/kakao_auth_repository.dart';
import '../provider/login_provider.dart';
import '../provider/user_provider.dart';
import 'login_screen.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  final KakaoSignupData? kakaoSignupData;
  final GoogleSignupData? googleSignupData;
  final AppleSignupData? appleSignupData;

  const SignUpScreen({super.key, this.kakaoSignupData, this.googleSignupData, this.appleSignupData});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nicknameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _validatedInviteCode;
  bool _isValidatingInviteCode = false;

  /// 에러 메시지에서 "Exception: " 제거
  String _cleanErrorMessage(dynamic error) {
    final message = error.toString();
    // "Exception: " 제거
    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }
    return message;
  }

  @override
  void initState() {
    super.initState();
    _loadPendingInviteCode();
    _setupDeepLinkListener();
  }

  /// 딥링크 콜백 설정 (실시간 수신용)
  void _setupDeepLinkListener() {
    final deepLinkService = DeepLinkService();
    deepLinkService.onInviteCodeReceived = (code) {
      if (mounted && _inviteCodeController.text.isEmpty) {
        print('SignUpScreen: 딥링크로 초대코드 수신: $code');
        setState(() {
          _inviteCodeController.text = code;
        });
        // 자동으로 초대코드 확인
        _autoValidateInviteCode(code);
      }
    };
  }

  /// 딥링크로 전달된 초대코드 자동 로드 (재시도 로직 포함)
  Future<void> _loadPendingInviteCode() async {
    final deepLinkService = DeepLinkService();

    // 첫 번째 시도
    var pendingCode = await deepLinkService.getPendingInviteCode();

    if (pendingCode != null && pendingCode.isNotEmpty && mounted) {
      print('SignUpScreen: 저장된 초대코드 로드: $pendingCode');
      setState(() {
        _inviteCodeController.text = pendingCode!;
      });
      // 자동으로 초대코드 확인
      _autoValidateInviteCode(pendingCode);
      return;
    }

    // 딥링크 처리가 아직 완료되지 않았을 수 있으므로 재시도
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: 500));
      if (!mounted) return;

      pendingCode = await deepLinkService.getPendingInviteCode();
      if (pendingCode != null && pendingCode.isNotEmpty) {
        print('SignUpScreen: 재시도 ${i + 1}회차에서 초대코드 로드: $pendingCode');
        setState(() {
          _inviteCodeController.text = pendingCode!;
        });
        // 자동으로 초대코드 확인
        _autoValidateInviteCode(pendingCode);
        return;
      }
    }

    print('SignUpScreen: 저장된 초대코드 없음');
  }

  /// 초대코드 자동 확인
  Future<void> _autoValidateInviteCode(String code) async {
    // 이미 확인 중이거나 확인된 경우 스킵
    if (_isValidatingInviteCode || _validatedInviteCode != null) return;

    print('SignUpScreen: 초대코드 자동 확인 시작: $code');

    setState(() {
      _isValidatingInviteCode = true;
    });

    try {
      final upperCode = code.trim().toUpperCase();
      final deviceId = await DeviceIdHelper.getDeviceId();
      final repo = ref.read(loginRepositoryProvider);
      final result = await repo.validateInviteCode(upperCode, deviceId);

      if (!mounted) return;

      if (result != null && result['inviterUid'] != null) {
        // 유효한 초대코드
        setState(() {
          _validatedInviteCode = upperCode;
          _isValidatingInviteCode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대코드가 확인되었습니다!')),
        );
      } else if (result != null && result['error'] == 'SAME_DEVICE_ERROR') {
        // 기기 중복 에러
        setState(() {
          _isValidatingInviteCode = false;
        });
        _inviteCodeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대코드는 딱 한번만 입력할 수 있습니다 (탈퇴 후 재가입 포함)')),
        );
      } else {
        // 기타 에러
        setState(() {
          _isValidatingInviteCode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효하지 않은 초대코드입니다')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidatingInviteCode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanErrorMessage(e))),
      );
    }
  }

  @override
  void dispose() {
    // 딥링크 콜백 정리
    DeepLinkService().onInviteCodeReceived = null;
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    // 소셜 로그인 정보가 없으면 회원가입 불가
    if (widget.kakaoSignupData == null && widget.googleSignupData == null && widget.appleSignupData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('소셜 로그인 정보가 없습니다. 다시 시도해주세요.')),
      );
      Navigator.pop(context);
      return;
    }

    // 신규 가입자 유심 체크

    if (Platform.isAndroid) {
      try {
        final hasSim = await SimCardManager.hasSimCard;
        if (!hasSim) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\'개통된 단말기\'에서만 이용 가능합니다.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('유심 체크 중 오류: $e');
        // 유심 체크 실패 시에도 가입 진행 (오류로 인해 정상 사용자 차단 방지)
      }
    }

    // 폼 검증
    if (!_formKey.currentState!.validate()) {
      print('폼 검증 실패');
      return;
    }

    // 이미 로딩 중이면 중복 실행 방지
    if (_isLoading) {
      print('이미 회원가입 진행 중');
      return;
    }

    print('회원가입 시작 - 닉네임: ${_nicknameController.text}');

    setState(() {
      _isLoading = true;
    });

    try {
      final nickname = _nicknameController.text.trim();

      // 광고 ID 가져오기
      final adId = await AdvertisingIdHelper.getAdvertisingId();
      // 기기 ID 가져오기
      final deviceId = await DeviceIdHelper.getDeviceId();
      print('회원가입 시 광고 ID: $adId');
      print('회원가입 시 기기 ID: $deviceId');
      print('사용한 초대코드: $_validatedInviteCode');

      // 카카오 또는 구글 로그인에 따라 분기 처리
      dynamic user;

      if (widget.kakaoSignupData != null) {
        // 카카오 회원가입
        final kakaoAuth = ref.read(kakaoAuthRepositoryProvider);
        user = await kakaoAuth.signUpWithKakao(
          kakaoId: widget.kakaoSignupData!.kakaoId,
          accessToken: widget.kakaoSignupData!.accessToken,
          accountEmail: widget.kakaoSignupData!.accountEmail,
          nickname: nickname,
          usedInviteCode: _validatedInviteCode,
          adId: adId,
          deviceId: deviceId,
        );
      } else if (widget.googleSignupData != null) {
        // 구글 회원가입
        final googleAuth = ref.read(googleAuthRepositoryProvider);
        user = await googleAuth.signUpWithGoogle(
          googleId: widget.googleSignupData!.googleId,
          googleIdToken: widget.googleSignupData!.idToken,
          accountEmail: widget.googleSignupData!.accountEmail,
          nickname: nickname,
          usedInviteCode: _validatedInviteCode,
          adId: adId,
          deviceId: deviceId,
        );
      } else if (widget.appleSignupData != null) {
        // 애플 회원가입
        final appleAuth = ref.read(appleAuthRepositoryProvider);
        user = await appleAuth.signUpWithApple(
          appleId: widget.appleSignupData!.appleId,
          appleIdToken: widget.appleSignupData!.idToken,
          accountEmail: widget.appleSignupData!.accountEmail,
          nickname: nickname,
          usedInviteCode: _validatedInviteCode,
          adId: adId,
          deviceId: deviceId,
        );
      }

      print('회원가입 결과: ${user != null}');

      if (user != null) {
        // 로그인 성공 - currentUserProvider 업데이트
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

        // 딥링크로 전달된 초대코드 삭제 (사용 완료)
        await DeepLinkService().clearPendingInviteCode();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_validatedInviteCode != null ? '회원가입이 완료되었습니다! 초대 보상 300,000 머니를 받았습니다!' : '회원가입이 완료되었습니다. 환영합니다!'),
              duration: Duration(seconds: 3),
            ),
          );
          // 약간의 지연 후 메인 화면으로 이동
          await Future.delayed(Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
          }
        }
      } else {
        print('회원가입 실패');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('회원가입에 실패했습니다. 다른 닉네임을 시도해보세요.')),
          );
        }
      }
    } catch (e) {
      print('회원가입 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        title: const Text('회원가입'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                30.heightBox,
                Icon(
                  Icons.person_add,
                  size: 80,
                  color: widget.kakaoSignupData != null ? Color(0xFFFEE500) : (widget.appleSignupData != null ? Colors.black : Colors.blue),
                ).centered(),
                25.heightBox,
                Text(
                  widget.kakaoSignupData != null ? '카카오 회원가입' : (widget.appleSignupData != null ? '애플 회원가입' : '구글 회원가입'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                  textAlign: TextAlign.center,
                ).centered(),
                10.heightBox,
                '닉네임과 초대코드를 입력해주세요'.text.size(14).color(Colors.grey[600]).center.make().centered(),
                30.heightBox,
                TextFormField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: '닉네임',
                    hintText: '한글, 영어, 숫자만 입력 가능 (10자 이내)',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.black38),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.black, width: 2),
                    ),
                    prefixIcon: const Icon(Icons.person, color: Colors.black),
                    helperText: '가입 후에는 닉네임(아이디) 변경이 불가합니다.',
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  maxLength: 10,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '닉네임을 입력해주세요';
                    }
                    final validCharacters = RegExp(r'^[가-힣a-zA-Z0-9]+$');
                    if (!validCharacters.hasMatch(value)) {
                      return '한글, 영어, 숫자만 입력 가능합니다';
                    }
                    return null;
                  },
                ),
                30.heightBox,
                // 초대코드 입력 (선택적)
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      '초대코드 (선택사항)'.text.size(14).bold.color(Colors.grey[700]).make(),
                      8.heightBox,
                      '초대코드를 입력하면 30만 머니를 받고 시작할 수 있어요!'.text.size(12).color(Colors.grey[600]).make(),
                      12.heightBox,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _inviteCodeController,
                              decoration: InputDecoration(
                                hintText: '초대코드 입력 (6~8자리)',
                                hintStyle: TextStyle(color: Colors.grey),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[400]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.black, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                counterText: '', // 글자 수 카운터 숨김
                              ),
                              maxLength: 8,
                              textCapitalization: TextCapitalization.characters,
                              enabled: _validatedInviteCode == null,
                            ),
                          ),
                          12.widthBox,
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isValidatingInviteCode || _validatedInviteCode != null
                                  ? null
                                  : () async {
                                      if (_inviteCodeController.text.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('초대코드를 입력해주세요'),
                                            duration: Duration(milliseconds: 7000),
                                          ),
                                        );
                                        return;
                                      }

                                      setState(() {
                                        _isValidatingInviteCode = true;
                                      });

                                      try {
                                        final code = _inviteCodeController.text.trim().toUpperCase();
                                        // 기기 ID 가져오기
                                        final deviceId = await DeviceIdHelper.getDeviceId();
                                        final repo = ref.read(loginRepositoryProvider);
                                        final result = await repo.validateInviteCode(code, deviceId);

                                        if (result != null && result['inviterUid'] != null) {
                                          // 유효한 초대코드
                                          setState(() {
                                            _validatedInviteCode = code;
                                            _isValidatingInviteCode = false;
                                          });
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('초대코드가 확인되었습니다!'),
                                                duration: Duration(milliseconds: 7000),
                                              ),
                                            );
                                          }
                                        } else if (result != null && result['error'] == 'SAME_DEVICE_ERROR') {
                                          // 기기 중복 에러
                                          setState(() => _isValidatingInviteCode = false);
                                          _inviteCodeController.clear();
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('초대코드는 딱 한번만 입력할 수 있습니다 (탈퇴 후 재가입 포함)'),
                                                duration: Duration(milliseconds: 7000),
                                              ),
                                            );
                                          }
                                        } else {
                                          // 기타 에러
                                          setState(() => _isValidatingInviteCode = false);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('유효하지 않은 초대코드입니다'),
                                                duration: Duration(milliseconds: 7000),
                                              ),
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        setState(() => _isValidatingInviteCode = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(_cleanErrorMessage(e)),
                                              duration: Duration(milliseconds: 7000),
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _validatedInviteCode != null ? Colors.green : Colors.black,
                                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isValidatingInviteCode
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _validatedInviteCode != null ? '확인완료' : '확인',
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_validatedInviteCode != null) ...[
                        8.heightBox,
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            4.widthBox,
                            '초대코드가 확인되었습니다!'.text.size(12).color(Colors.green).make(),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                30.heightBox,

                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.kakaoSignupData != null
                        ? Color(0xFFFEE500)
                        : (widget.appleSignupData != null ? Colors.black : Colors.white),
                    foregroundColor: widget.kakaoSignupData != null
                        ? Color(0xFF3C1E1E)
                        : (widget.appleSignupData != null ? Colors.white : Colors.black87),
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: widget.kakaoSignupData != null
                                ? Color(0xFF3C1E1E)
                                : (widget.appleSignupData != null ? Colors.white : Colors.blue),
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.kakaoSignupData != null ? '카카오로 회원가입' : (widget.appleSignupData != null ? 'Apple로 회원가입' : '구글로 회원가입'),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ).h(60),
                30.heightBox,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
