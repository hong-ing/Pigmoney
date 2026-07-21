package com.reviewtube.pigmoney

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.pincrux.offerwall.PincruxOfferwall
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class MainActivity : FlutterFragmentActivity() {
    private val offerwall: PincruxOfferwall by lazy { PincruxOfferwall.getInstance() }
    private val appDetectorChannel = "com.pigmoney/app_detector"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 커스텀 네이티브 광고 팩토리 등록
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "customNativeAd200",
            CustomNativeAdFactory(layoutInflater)
        )

        // 만보기 MethodChannel
        val pedometerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pigmoney/pedometer")
        pedometerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, StepCounterService::class.java)
                    startForegroundService(intent)
                    result.success(true)
                }

                "stopService" -> {
                    stopService(Intent(this, StepCounterService::class.java))
                    result.success(true)
                }

                "getTodaySteps" -> {
                    val prefs = getSharedPreferences(StepCounterService.PREF_NAME, MODE_PRIVATE)

                    // 자정 이후 서비스가 센서 이벤트 없이 리셋 못 한 경우 대비
                    val kst = ZonedDateTime.now(ZoneId.of("Asia/Seoul"))
                    val currentDate = kst.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
                    val lastResetDate = prefs.getString(StepCounterService.KEY_LAST_RESET_DATE, "") ?: ""

                    if (lastResetDate.isNotEmpty() && lastResetDate != currentDate) {
                        // 날짜 변경 → 걸음수 0 리셋 + 센서 기준점 초기화
                        prefs.edit()
                            .putInt(StepCounterService.KEY_TODAY_STEPS, 0)
                            .putInt(StepCounterService.KEY_PREVIOUS_SENSOR, -1)
                            .putString(StepCounterService.KEY_LAST_RESET_DATE, currentDate)
                            .putString(StepCounterService.KEY_NOTIFIED_MILESTONES, "")
                            .commit()

                        // 서비스 실행 중이면 메모리도 동기화
                        if (StepCounterService.isRunning) {
                            try {
                                val reloadIntent = Intent(this, StepCounterService::class.java).apply {
                                    action = StepCounterService.ACTION_RELOAD_STEPS
                                }
                                startService(reloadIntent)
                            } catch (_: Exception) {
                            }
                        }

                        result.success(0)
                    } else {
                        result.success(prefs.getInt(StepCounterService.KEY_TODAY_STEPS, 0))
                    }
                }

                "setTodaySteps" -> {
                    val steps = call.argument<Int>("steps") ?: 0
                    val prefs = getSharedPreferences(StepCounterService.PREF_NAME, MODE_PRIVATE)

                    // 자정 기준 날짜 저장 (서비스의 getStepDateKey()와 동일 기준)
                    val kst = ZonedDateTime.now(ZoneId.of("Asia/Seoul"))
                    val currentDate = kst.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))

                    prefs.edit()
                        .putInt(StepCounterService.KEY_TODAY_STEPS, steps)
                        .putString(StepCounterService.KEY_LAST_RESET_DATE, currentDate)
                        .commit()

                    // 서비스가 실행 중이면 메모리 동기화 요청
                    if (StepCounterService.isRunning) {
                        try {
                            val reloadIntent = Intent(this, StepCounterService::class.java).apply {
                                action = StepCounterService.ACTION_RELOAD_STEPS
                            }
                            startService(reloadIntent) // startForegroundService가 아닌 startService
                        } catch (_: Exception) {
                        }
                    }

                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // 만보기 EventChannel (실시간 걸음수 스트림)
        val stepEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pigmoney/pedometer_steps")
        stepEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            var receiver: BroadcastReceiver? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                receiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        events.success(intent.getIntExtra("steps", 0))
                    }
                }
                ContextCompat.registerReceiver(
                    this@MainActivity,
                    receiver!!,
                    IntentFilter(StepCounterService.ACTION_STEP_UPDATE),
                    ContextCompat.RECEIVER_NOT_EXPORTED
                )
            }

            override fun onCancel(arguments: Any?) {
                receiver?.let { unregisterReceiver(it) }
                receiver = null
            }
        })

        // 디버깅 감지 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pigmoney/device_security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUsbDebuggingEnabled" -> result.success(isUsbDebuggingEnabled())
                    "isWirelessDebuggingEnabled" -> result.success(isWirelessDebuggingEnabled())
                    else -> result.notImplemented()
                }
            }

        // Pincrux Offerwall 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "init" -> {
                            val pubkey: String? = call.argument("pubkey")
                            val usrkey: String? = call.argument("usrkey")
                            offerwall.init(this@MainActivity, pubkey, usrkey)
                            result.success(null)
                        }

                        "startOfferwall" -> {
                            offerwall.startPincruxOfferwallActivity(this@MainActivity)
                            result.success(null)
                        }

                        "startPincruxOfferwallViewType" -> {
                            val intent = Intent(this@MainActivity, PincruxViewTypeActivity::class.java)
                            startActivity(intent)
                            result.success(null)
                        }

                        "startPincruxOfferwallAdDetail" -> {
                            val appkey: String? = call.argument("appkey")
                            offerwall.startPincruxOfferwallDetailActivity(this@MainActivity, appkey)
                            result.success(null)
                        }

                        "startPincruxOfferwallContact" -> {
                            offerwall.startPincruxContactActivity(this@MainActivity)
                            result.success(null)
                        }

                        "setOfferwallType" -> {
                            val type: Int = call.argument<Int>("type") ?: 0
                            offerwall.setOfferwallType(type)
                            result.success(null)
                        }

                        "setEnableTab" -> {
                            val isEnable: Boolean = call.argument<Boolean>("isEnable") ?: false
                            offerwall.setEnableTab(isEnable)
                            result.success(null)
                        }

                        "setOfferwallTitle" -> {
                            val title: String? = call.argument("title")
                            offerwall.setOfferwallTitle(title)
                            result.success(null)
                        }

                        "setOfferwallThemeColor" -> {
                            val color: String? = call.argument("color")
                            offerwall.setOfferwallThemeColor(color)
                            result.success(null)
                        }

                        "setEnableScrollTopButton" -> {
                            val isEnable: Boolean = call.argument<Boolean>("isEnable") ?: false
                            offerwall.setEnableScrollTopButton(isEnable)
                            result.success(null)
                        }

                        "setAdDetail" -> {
                            val isEnable: Boolean = call.argument<Boolean>("isEnable") ?: false
                            offerwall.setAdDetail(isEnable)
                            result.success(null)
                        }

                        "setDisableCPS" -> {
                            val isDisable: Boolean = call.argument<Boolean>("isDisable") ?: false
                            offerwall.setDisableCPS(isDisable)
                            result.success(null)
                        }

                        "setDarkMode" -> {
                            val darkmode: Int = call.argument<Int>("mode") ?: 0
                            offerwall.setDarkMode(darkmode)
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("PINCRUX_ERROR", e.message, null)
                }
            }
    }

    companion object {
        private const val methodChannelName = "com.pincrux.offerwall.flutter"
    }


    // USB 디버깅 활성화 여부 확인
    private fun isUsbDebuggingEnabled(): Boolean {
        return try {
            Settings.Global.getInt(contentResolver, Settings.Global.ADB_ENABLED, 0) == 1
        } catch (e: Exception) {
            false
        }
    }

    // 무선 디버깅(ADB over WiFi) 활성화 여부 확인 (Android 11+)
    private fun isWirelessDebuggingEnabled(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Settings.Global.getInt(contentResolver, "adb_wifi_enabled", 0) == 1
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    // 패키지 설치 여부 확인
    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    // 앱 실행 여부 확인 (Android 5.0 이상에서는 제한적)
    private fun isAppRunning(packageName: String): Boolean {
        // Android 5.0 이상에서는 다른 앱의 실행 상태를 직접 확인할 수 없음
        // 대신 설치 여부만 확인
        return isPackageInstalled(packageName)
    }

    // 가상 환경 감지
    private fun isVirtualEnvironment(): Boolean {
        // 여러 가상 환경 특징을 확인
        return checkEmulator() || checkVirtualApps() || checkMultipleAccounts()
    }

    // 에뮬레이터 확인
    private fun checkEmulator(): Boolean {
        return (Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.BOARD == "QC_Reference_Phone"
                || Build.MANUFACTURER.contains("Genymotion")
                || Build.HOST.startsWith("Build")
                || (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
                || "google_sdk" == Build.PRODUCT)
    }

    // 가상 앱 환경 확인
    private fun checkVirtualApps(): Boolean {
        val virtualAppsPaths = arrayOf(
            "/data/data/com.lody.virtual",
            "/data/data/com.excelliance.multiaccounts",
            "/data/data/com.polestar.multiaccount",
            "/data/data/com.parallel.space.lite",
            "/data/data/com.ludashi.dualspace"
        )

        for (path in virtualAppsPaths) {
            if (File(path).exists()) {
                return true
            }
        }

        return false
    }

    // 다중계정 환경 특징 확인
    private fun checkMultipleAccounts(): Boolean {
        // 다중계정 앱들이 사용하는 특정 프로세스나 파일 확인
        val suspiciousFiles = arrayOf(
            "/data/misc/virtual",
            "/data/misc/parallel",
            "/data/misc/multi"
        )

        for (file in suspiciousFiles) {
            if (File(file).exists()) {
                return true
            }
        }

        // 패키지 경로가 비정상적인지 확인
        val packagePath = applicationContext.packageCodePath
        if (packagePath.contains("virtual") ||
            packagePath.contains("parallel") ||
            packagePath.contains("multi") ||
            packagePath.contains("clone")
        ) {
            return true
        }

        return false
    }
}
