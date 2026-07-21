import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../core/services/device_check_service.dart';
import '../../core/utils/advertising_id_helper.dart';
import '../../core/utils/pref/pref_util.dart';
import '../../core/utils/pref/secure_storage_util.dart';
import '../../data/login/apple_auth_repository.dart';
import '../../data/login/google_auth_repository.dart';
import '../../data/login/kakao_auth_repository.dart';
import '../../main.dart' show checkForEventPopupAfterLogin;
import '../provider/attendance_provider.dart';
import '../provider/game2/game2_provider.dart';
import '../provider/login_provider.dart';
import '../provider/user_provider.dart';
import '../provider/work_provider.dart';
import 'sign_up_screen.dart';

// Provider for Kakao auth repository
final kakaoAuthRepositoryProvider = Provider<KakaoAuthRepository>((ref) {
  return KakaoAuthRepository();
});

// Provider for Google auth repository
final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  return GoogleAuthRepository();
});

// Provider for Apple auth repository
final appleAuthRepositoryProvider = Provider<AppleAuthRepository>((ref) {
  return AppleAuthRepository();
});

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _showLegacyLogin = false; // 기존 로그인 폼 표시 여부

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
    // 로그인 화면 진입 시 캐시 정리
    _clearCacheOnInit();
    // 저장된 로그인 정보 불러오기
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final savedNickname = PrefUtil.getString('saved_nickname');
      final savedPassword = await SecureStorageUtil.read('saved_password');

      // SharedPreferences에 남아있는 기존 비밀번호를 Secure Storage로 마이그레이션
      if (savedPassword == null) {
        final legacyPassword = PrefUtil.getString('saved_password');
        if (legacyPassword != null && savedNickname != null) {
          await SecureStorageUtil.write('saved_password', legacyPassword);
          await PrefUtil.remove('saved_password');
          setState(() {
            _nicknameController.text = savedNickname;
            _passwordController.text = legacyPassword;
          });
          return;
        }
      }

      if (savedNickname != null && savedPassword != null) {
        setState(() {
          _nicknameController.text = savedNickname;
          _passwordController.text = savedPassword;
        });
      }
    } catch (e) {
      print('저장된 로그인 정보 불러오기 실패: $e');
    }
  }

  Future<void> _clearCacheOnInit() async {
    try {
      print('로그인 화면: 캐시 정리 시작');

      // 1. Firebase Auth 상태 확인 - 이미 로그인 상태면 캐시 클리어 안함
      final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
      if (isLoggedIn) {
        print('로그인 화면: 이미 로그인 상태 - 캐시 클리어 스킵');
        return; // 로그인 상태면 캐시 클리어하지 않고 종료
      }

      // 2. 로그인 정보를 임시 저장
      final savedNickname = PrefUtil.getString('saved_nickname');
      final savedPassword = await SecureStorageUtil.read('saved_password');

      // 3. SharedPreferences 클리어
      await PrefUtil.clear();

      // 4. 로그인 정보 복원
      if (savedNickname != null) {
        await PrefUtil.setString('saved_nickname', savedNickname);
      }
      if (savedPassword != null) {
        await SecureStorageUtil.write('saved_password', savedPassword);
      }

      // 5. UserRepository의 캐시 정리
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.clearCachedUserData();

      // 6. 모든 프로바이더 무효화
      // ✅ game2Provider/workProvider는 keepAlive(비-autoDispose)라 앱 프로세스가
      // 살아있는 동안 이전 계정의 게임 상태가 메모리에 남음 (탈퇴 후 재가입 시
      // 머니팡팡이 이전 진행 단계부터 시작하는 버그) → 반드시 함께 무효화
      try {
        ref.invalidate(userDataProvider);
        ref.invalidate(dailyEarningsProvider);
        ref.invalidate(monthlyEarningsProvider);
        ref.invalidate(dailyRankingsProvider);
        ref.invalidate(monthlyRankingsProvider);
        ref.invalidate(attendanceManagerProvider);
        ref.invalidate(game2Provider);
        ref.invalidate(workProvider);
      } catch (e) {
        print('프로바이더 무효화 중 오류 (무시): $e');
      }

      print('로그인 화면: 캐시 정리 완료');
    } catch (e) {
      print('로그인 화면: 캐시 정리 중 오류 (무시): $e');
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = ref.read(loginRepositoryProvider);
      final user = await repo.login(
        _nicknameController.text.trim(),
        _passwordController.text,
      );
      final success = user != null;

      if (success) {
        // 로그인 성공 시 아이디와 비밀번호 저장
        await PrefUtil.setString('saved_nickname', _nicknameController.text.trim());
        await SecureStorageUtil.write('saved_password', _passwordController.text);

        // 로그인 성공 시 currentUserProvider 상태 명시적으로 초기화 (강제 새로고침)
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

        // 기기 검증 수행
        if (mounted) {
          final deviceResult = await deviceCheckService.checkDevice(context: context);
          if (deviceResult == DeviceCheckResult.mismatch) {
            // 기기 불일치 - 다이얼로그가 이미 표시됨, 앱 종료됨
            return;
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
          print('로그인 성공');

          // 로그인 후 이벤트 팝업 체크
          checkForEventPopupAfterLogin();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인에 실패했습니다. 닉네임과 비밀번호를 확인해주세요.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e))),
        );
        print('로그인 실패 : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithKakao() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final kakaoAuth = ref.read(kakaoAuthRepositoryProvider);
      final result = await kakaoAuth.signInWithKakao();

      if (result == null) {
        // 사용자가 취소했거나 오류 발생
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('카카오 로그인이 취소되었습니다.')),
          );
        }
        return;
      }

      if (result.isNewUser) {
        // 신규 사용자 - 회원가입 화면으로 이동
        if (mounted) {
          print('신규 사용자 - 회원가입 화면으로 이동');
          // 카카오 정보를 회원가입 화면으로 전달
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SignUpScreen(kakaoSignupData: result.signupData),
            ),
          );
        }
      } else if (result.user != null) {
        // 기존 사용자 - 로그인 성공
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

        // 기기 검증 수행
        if (mounted) {
          final deviceResult = await deviceCheckService.checkDevice(context: context);
          if (deviceResult == DeviceCheckResult.mismatch) {
            // 기기 불일치 - 다이얼로그가 이미 표시됨, 앱 종료됨
            return;
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
          print('카카오 로그인 성공');

          // 로그인 후 이벤트 팝업 체크
          checkForEventPopupAfterLogin();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e))),
        );
        print('카카오 로그인 실패 : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final googleAuth = ref.read(googleAuthRepositoryProvider);
      final result = await googleAuth.signInWithGoogle();

      if (result == null) {
        // 사용자가 취소했거나 오류 발생
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('구글 로그인이 취소되었습니다.')),
          );
        }
        return;
      }

      if (result.isNewUser) {
        // 신규 사용자 - 회원가입 화면으로 이동
        if (mounted) {
          print('신규 사용자 - 회원가입 화면으로 이동');
          // 구글 정보를 회원가입 화면으로 전달
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SignUpScreen(googleSignupData: result.signupData),
            ),
          );
        }
      } else if (result.user != null) {
        // 기존 사용자 - 로그인 성공
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

        // 기기 검증 수행
        if (mounted) {
          final deviceResult = await deviceCheckService.checkDevice(context: context);
          if (deviceResult == DeviceCheckResult.mismatch) {
            // 기기 불일치 - 다이얼로그가 이미 표시됨, 앱 종료됨
            return;
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
          print('구글 로그인 성공');

          // 로그인 후 이벤트 팝업 체크
          checkForEventPopupAfterLogin();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e))),
        );
        print('구글 로그인 실패 : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithApple() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appleAuth = ref.read(appleAuthRepositoryProvider);
      final result = await appleAuth.signInWithApple();

      if (result == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('애플 로그인이 취소되었습니다.')),
          );
        }
        return;
      }

      if (result.isNewUser) {
        if (mounted) {
          print('신규 사용자 - 회원가입 화면으로 이동');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SignUpScreen(appleSignupData: result.signupData),
            ),
          );
        }
      } else if (result.user != null) {
        await ref.read(currentUserProvider.notifier).fetchCurrentUser(forceRefresh: true);

        if (mounted) {
          final deviceResult = await deviceCheckService.checkDevice(context: context);
          if (deviceResult == DeviceCheckResult.mismatch) {
            return;
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
          print('애플 로그인 성공');

          checkForEventPopupAfterLogin();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cleanErrorMessage(e))),
        );
        print('애플 로그인 실패 : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Image.asset('assets/icons/ic_logo.png', width: 160, height: 160).centered(),
              '피그머니'.text.size(28).bold.white.center.make().centered(),
              if(_showLegacyLogin) 40.heightBox else 80.heightBox,

              // 기존 로그인 폼 (닉네임, 비밀번호, 로그인 버튼)
              if (_showLegacyLogin) ...[
                TextFormField(
                  controller: _nicknameController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '닉네임',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: Colors.white),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '닉네임을 입력해주세요';
                    }
                    return null;
                  },
                ).px20(),
                16.heightBox,
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock, color: Colors.white),
                  ),
                  keyboardType: TextInputType.text,
                  obscureText: true,
                  style: TextStyle(color: Colors.white),
                  maxLength: 8,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '비밀번호를 입력해주세요';
                    }
                    if (value.length < 8) {
                      return '비밀번호는 8자리 이어야 합니다.';
                    }
                    return null;
                  },
                ).px20(),
                30.heightBox,
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('로그인', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ).px20().h(55),
                20.heightBox,
              ],

              // 소셜 로그인 버튼들 (항상 표시)
              Container(
                height: 54,
                margin: EdgeInsets.symmetric(horizontal: 20),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _loginWithKakao,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: Colors.black.withOpacity(0.1),
                    highlightColor: Colors.black.withOpacity(0.05),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Color(0xFFFEE500),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isLoading
                          ? Container(
                              decoration: BoxDecoration(color: Color(0xFFFEE500), borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                child: CircularProgressIndicator(color: Color(0xFF3C1E1E)),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset('assets/icons/ic_kakao.png', width: 24, height: 24),
                                12.widthBox,
                                Text(
                                  '카카오로 로그인하기',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              12.heightBox,

              // 구글 로그인 버튼
              Container(
                height: 54,
                margin: EdgeInsets.symmetric(horizontal: 20),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _loginWithGoogle,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: Colors.grey.withOpacity(0.1),
                    highlightColor: Colors.grey.withOpacity(0.05),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isLoading
                          ? Center(child: CircularProgressIndicator(color: Colors.blue))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset('assets/icons/ic_google.png', width: 24, height: 24),
                                12.widthBox,
                                Text(
                                  '구글로 로그인하기',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),

              // 애플 로그인 버튼 (iOS만 표시)
              if (Platform.isIOS) ...[
                12.heightBox,
                Container(
                  height: 54,
                  margin: EdgeInsets.symmetric(horizontal: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading ? null : _loginWithApple,
                      borderRadius: BorderRadius.circular(12),
                      splashColor: Colors.white.withOpacity(0.1),
                      highlightColor: Colors.white.withOpacity(0.05),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: _isLoading
                            ? Center(child: CircularProgressIndicator(color: Colors.white))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.apple, color: Colors.white, size: 26),
                                  12.widthBox,
                                  Text(
                                    'Apple로 로그인하기',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],

              // 기존 방식으로 로그인 버튼 (하단에 배치)
              const Spacer(),
              if (!_showLegacyLogin)
                GestureDetector(
                  onTap: () {
                    setState(() => _showLegacyLogin = !_showLegacyLogin);
                  },
                  child: '기존 방식으로 로그인'.text.size(14).white.medium.center.make(),
                ),
              40.heightBox,
            ],
          ),
        ),
      ),
    );
  }
}
