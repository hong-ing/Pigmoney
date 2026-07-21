import 'package:flutter/services.dart';
import 'dart:io';

class MultiAccountDetector {
  static const MethodChannel _channel = MethodChannel('com.pigmoney/app_detector');

  // 차단할 다중계정 앱 패키지 목록
  static const List<String> _blockedPackages = [
    'com.excelliance.multiaccounts',
    'com.lody.virtual',
    'com.polestar.multiaccount',
    'com.jumobile.multiaccounts',
    'com.applisto.appcloner',
    'com.parallel.space.lite',
    'com.lbe.parallel.intl.arm64',
    'com.multiplebox.droidapps',
    'com.ludashi.dualspace',
    'com.excean.parallelspace',
    'com.excelliance.multiaccount',
    'multi.parallel.dualspace.cloner',
    'com.pengyou.cloneapp',
    'com.cmaster.cloner',
    'com.excelliance.multiaccounts.b32',
    'co.keeptop.multi.space',
    'com.clone.android.dual.space',
    'com.dong.multirun',
    'com.ludashi.superboost',
    'grape.products.keyhop',
    'com.waxmoon.ma.gp',
    'com.pspace.vandroid',
    'com.polestar.super.clone',
    'virtual.app.clone.app',
    'com.mtech.multiple',
    'com.xunijun.app.gp',
    'do.multiple.cloner',
  ];

  // 앱이 설치되어 있는지 확인
  static Future<bool> isMultiAccountAppInstalled() async {
    if (!Platform.isAndroid) return false;

    try {
      for (String packageName in _blockedPackages) {
        final bool isInstalled = await _channel.invokeMethod(
          'isAppInstalled',
          {'packageName': packageName},
        );

        if (isInstalled) {
          print('Detected multi-account app: $packageName');
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking for multi-account apps: $e');
      return false;
    }
  }

  // 앱이 실행 중인지 확인
  static Future<bool> isMultiAccountAppRunning() async {
    if (!Platform.isAndroid) return false;

    try {
      for (String packageName in _blockedPackages) {
        final bool isRunning = await _channel.invokeMethod(
          'isAppRunning',
          {'packageName': packageName},
        );

        if (isRunning) {
          print('Detected running multi-account app: $packageName');
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error checking running apps: $e');
      return false;
    }
  }

  // 가상 환경 감지 (다중계정 앱의 특징)
  static Future<bool> isRunningInVirtualEnvironment() async {
    if (!Platform.isAndroid) return false;

    try {
      final bool isVirtual = await _channel.invokeMethod('isVirtualEnvironment');
      return isVirtual;
    } catch (e) {
      print('Error checking virtual environment: $e');
      return false;
    }
  }

  // 종합 체크
  static Future<bool> detectMultiAccountApp() async {
    final bool isInstalled = await isMultiAccountAppInstalled();
    final bool isRunning = await isMultiAccountAppRunning();
    final bool isVirtual = await isRunningInVirtualEnvironment();

    return isInstalled || isRunning || isVirtual;
  }
}