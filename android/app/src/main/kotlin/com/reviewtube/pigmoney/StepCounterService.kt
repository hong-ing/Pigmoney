package com.reviewtube.pigmoney

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.text.SpannableStringBuilder
import android.text.style.StyleSpan
import android.util.Log
import androidx.core.app.NotificationCompat
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class StepCounterService : Service(), SensorEventListener {

    companion object {
        const val PREF_NAME = "FlutterForegroundTaskData"
        const val KEY_TODAY_STEPS = "fg_today_steps"
        const val KEY_LAST_RESET_DATE = "fg_last_reset_date"
        const val KEY_NOTIFIED_MILESTONES = "fg_notified_milestones"
        const val KEY_PREVIOUS_SENSOR = "fg_previous_sensor"

        const val ACTION_STEP_UPDATE = "com.reviewtube.pigmoney.STEP_UPDATE"
        const val ACTION_RELOAD_STEPS = "com.reviewtube.pigmoney.RELOAD_STEPS"
        const val NOTIFICATION_CHANNEL_ID = "pedometer_fg"
        const val MILESTONE_CHANNEL_ID = "step_milestone_channel"
        const val NOTIFICATION_ID = 200

        @Volatile
        var isRunning = false
    }

    private lateinit var prefs: SharedPreferences
    private var sensorManager: SensorManager? = null
    private var sensorRegistered = false

    // 센서 전용 백그라운드 스레드 (메인 스레드 블로킹 방지)
    private var sensorThread: HandlerThread? = null
    private var sensorHandler: Handler? = null

    // CashRound 패턴: 메모리 기반 previousStepCount (-1 = 초기값, 센서 첫 이벤트에서 기준점 설정)
    private var previousStepCount = -1
    private var stepCount = 0

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        prefs = getSharedPreferences(PREF_NAME, MODE_PRIVATE)
        sensorManager = getSystemService(SENSOR_SERVICE) as? SensorManager

        // 센서 이벤트 전용 스레드 시작
        sensorThread = HandlerThread("StepSensorThread").also {
            it.start()
            sensorHandler = Handler(it.looper)
        }

        loadStepCount()
        registerSensorIfNeeded()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        registerSensorIfNeeded()

        // Flutter에서 setTodaySteps 호출 후 메모리 동기화 요청
        if (intent?.action == ACTION_RELOAD_STEPS) {
            stepCount = prefs.getInt(KEY_TODAY_STEPS, 0)
            previousStepCount = prefs.getInt(KEY_PREVIOUS_SENSOR, -1)
            broadcastSteps(stepCount)
            updateForegroundNotification(stepCount)
            return START_STICKY
        }

        // Foreground 알림 생성 (항상 foreground로 유지)
        try {
            createNotificationChannel()
            createMilestoneNotificationChannel()
            val notification = buildNotification(stepCount)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e("StepCounterService", "Failed to start foreground", e)
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    private fun registerSensorIfNeeded() {
        if (sensorRegistered) return
        val stepSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (stepSensor != null) {
            // sensorHandler: 센서 이벤트를 전용 스레드에서 수신 (메인 스레드 부하 방지)
            // maxReportLatencyUs=0: 센서 이벤트 즉시 전달 (배칭 방지)
            val ok = sensorManager?.registerListener(
                this, stepSensor, SensorManager.SENSOR_DELAY_FASTEST, 0, sensorHandler
            ) ?: false
            sensorRegistered = ok
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // 앱이 최근 앱 목록에서 제거됨 -> 서비스 재시작 (CashRound 패턴)
        Log.d("StepCounterService", "onTaskRemoved - 서비스 재시작 시도")
        try {
            val restartIntent = Intent(applicationContext, StepCounterService::class.java)
            startForegroundService(restartIntent)
        } catch (e: Exception) {
            Log.e("StepCounterService", "서비스 재시작 실패", e)
        }
    }

    override fun onDestroy() {
        isRunning = false
        sensorManager?.unregisterListener(this)
        sensorThread?.quitSafely()
        sensorThread = null
        sensorHandler = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── SensorEventListener ───

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_STEP_COUNTER) return
        val currentSensor = event.values[0].toInt()

        // 날짜 리셋 체크 (자정 기준)
        val currentDate = getStepDateKey()
        val lastResetDate = prefs.getString(KEY_LAST_RESET_DATE, "") ?: ""

        if (lastResetDate != currentDate) {
            // 날짜 변경 -> 걸음수 리셋
            stepCount = 0
            previousStepCount = currentSensor
            prefs.edit()
                .putInt(KEY_TODAY_STEPS, 0)
                .putInt(KEY_PREVIOUS_SENSOR, currentSensor)
                .putString(KEY_LAST_RESET_DATE, currentDate)
                .putString(KEY_NOTIFIED_MILESTONES, "")
                .apply()
            broadcastSteps(0)
            updateForegroundNotification(0)
            return
        }

        // 첫 센서값: previousStepCount가 -1이면 저장된 값이 없는 최초 실행
        if (previousStepCount == -1) {
            previousStepCount = currentSensor
            prefs.edit().putInt(KEY_PREVIOUS_SENSOR, currentSensor).apply()
            broadcastSteps(stepCount)
            updateForegroundNotification(stepCount)
            return
        }

        // delta 계산 (서비스 재시작 시에도 저장된 previousStepCount로 정확한 delta 산출)
        val delta = currentSensor - previousStepCount
        if (delta > 0) {
            stepCount += delta
            previousStepCount = currentSensor
            prefs.edit()
                .putInt(KEY_TODAY_STEPS, stepCount)
                .putInt(KEY_PREVIOUS_SENSOR, currentSensor)
                .apply()
            broadcastSteps(stepCount)
            updateForegroundNotification(stepCount)
            checkAndSendMilestoneNotification(stepCount)
        } else if (delta < 0) {
            // 기기 재부팅으로 센서 리셋 -> 새 기준점 저장 (걸음수 유지)
            previousStepCount = currentSensor
            prefs.edit().putInt(KEY_PREVIOUS_SENSOR, currentSensor).apply()
        }
        // delta == 0: 변화 없음
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ─── 자정 기준 날짜 (걸음수 리셋용) ───

    private fun getStepDateKey(): String {
        val kst = ZonedDateTime.now(ZoneId.of("Asia/Seoul"))
        return kst.format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
    }

    // ─── 서비스 시작 시 상태 복원 ───

    private fun loadStepCount() {
        val lastResetDate = prefs.getString(KEY_LAST_RESET_DATE, "") ?: ""
        val currentDate = getStepDateKey()

        if (lastResetDate != currentDate) {
            // 날짜 바뀜 -> 걸음수 리셋
            stepCount = 0
            previousStepCount = -1
            prefs.edit()
                .putInt(KEY_TODAY_STEPS, 0)
                .putInt(KEY_PREVIOUS_SENSOR, -1)
                .putString(KEY_LAST_RESET_DATE, currentDate)
                .putString(KEY_NOTIFIED_MILESTONES, "")
                .apply()
            Log.d("StepCounterService", "날짜 변경으로 걸음 수 초기화")
        } else {
            // 같은 날 -> 저장된 걸음수 + 센서 기준점 복원
            stepCount = prefs.getInt(KEY_TODAY_STEPS, 0)
            previousStepCount = prefs.getInt(KEY_PREVIOUS_SENSOR, -1)
            Log.d("StepCounterService", "저장된 걸음 수 불러옴: $stepCount, 센서 기준점: $previousStepCount")
        }
    }

    // ─── Foreground 알림 (실시간 걸음수 표시) ───

    private fun buildNotification(steps: Int = 0): Notification {
        val styledText = getNotificationStyledText(steps)
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_work_noti)
            .setContentTitle("피그머니 만보기")
            .setContentText(styledText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(styledText))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }

    private fun getNotificationStyledText(steps: Int): CharSequence {
        val formatted = String.format("%,d", steps)
        val text = when {
            steps >= 10000 -> "\uD83D\uDC51 ${formatted}걸음\n상자 5개 전부 최대 보상 가능!"
            steps >= 2000 -> {
                val boxes = minOf(steps / 2000, 5)
                "\uD83D\uDC63 ${formatted}걸음\n상자 ${boxes}개 최대 보상 가능"
            }
            else -> {
                val remaining = String.format("%,d", 2000 - steps)
                "\uD83D\uDC63 현재 ${formatted}걸음\n2,000걸음까지 ${remaining}걸음 남았어요!"
            }
        }
        val ssb = SpannableStringBuilder(text)
        val start = text.indexOf(formatted)
        if (start >= 0) {
            ssb.setSpan(StyleSpan(Typeface.BOLD), start, start + formatted.length, 0)
        }
        return ssb
    }

    private fun updateForegroundNotification(steps: Int) {
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            nm.notify(NOTIFICATION_ID, buildNotification(steps))
        } catch (e: Exception) {
            Log.e("StepCounterService", "알림 업데이트 실패", e)
        }
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java) ?: return

        // 기존 LOW 채널 제거 (중요도 변경은 채널 재생성 필요)
        nm.deleteNotificationChannel("pedometer_silent")

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "만보기",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "걸음수를 백그라운드에서 측정합니다"
            lockscreenVisibility = Notification.VISIBILITY_SECRET
            setSound(null, null)
            setShowBadge(false)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    // ─── 걸음수 마일스톤 알림 ───

    private fun createMilestoneNotificationChannel() {
        val channel = NotificationChannel(
            MILESTONE_CHANNEL_ID,
            "걸음수 알림",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "걸음수 목표 달성 알림"
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm?.createNotificationChannel(channel)
    }

    private fun isWorkNotificationEnabled(): Boolean {
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return flutterPrefs.getBoolean("flutter.pref_work_alarm", true)
    }

    private fun getNotifiedMilestones(): Set<Int> {
        val stored = prefs.getString(KEY_NOTIFIED_MILESTONES, "") ?: ""
        if (stored.isBlank()) return emptySet()
        return stored.split(",").mapNotNull { it.toIntOrNull() }.toSet()
    }

    private fun markMilestoneNotified(milestone: Int) {
        val current = getNotifiedMilestones().toMutableSet()
        current.add(milestone)
        prefs.edit().putString(KEY_NOTIFIED_MILESTONES, current.joinToString(",")).apply()
    }

    private fun checkAndSendMilestoneNotification(steps: Int) {
        if (!isWorkNotificationEnabled()) return

        val milestones = listOf(2000, 4000, 6000, 8000, 10000)
        val notified = getNotifiedMilestones()

        for (milestone in milestones) {
            if (steps >= milestone && milestone !in notified) {
                sendMilestoneNotification(milestone)
                markMilestoneNotified(milestone)
            }
        }
    }

    private fun sendMilestoneNotification(milestone: Int) {
        val body = when (milestone) {
            2000 -> "\uD83D\uDC63 2,000걸음 달성! 첫 상자 최대 보상 가능"
            4000 -> "\uD83D\uDEB6 4,000걸음 달성! 두 번째 상자 보너스 준비 완료"
            6000 -> "\uD83D\uDD25 6,000걸음 달성! 상자 3개 최대 보상 가능"
            8000 -> "\uD83D\uDE80 8,000걸음 달성! 1만보까지 조금만 더!"
            10000 -> "\uD83D\uDC51 10,000걸음 달성! 오늘 최대 보상 완성 \uD83C\uDF89"
            else -> return
        }

        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            val notificationId = 100 + milestone / 2000 // 101~105
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            }
            val pendingIntent = PendingIntent.getActivity(
                this, notificationId, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(this, MILESTONE_CHANNEL_ID)
                .setContentTitle("피그머니 만보기")
                .setContentText(body)
                .setSmallIcon(R.drawable.ic_work_noti)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            nm.notify(notificationId, notification)
        } catch (e: Exception) {
            Log.e("StepCounterService", "마일스톤 알림 실패", e)
        }
    }

    // ─── Broadcast ───

    private fun broadcastSteps(steps: Int) {
        val intent = Intent(ACTION_STEP_UPDATE).apply {
            putExtra("steps", steps)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }
}
