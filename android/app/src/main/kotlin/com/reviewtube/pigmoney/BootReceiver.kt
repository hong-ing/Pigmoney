package com.reviewtube.pigmoney

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED || action == "android.intent.action.QUICKBOOT_POWERON") {
            // 만보기를 사용한 적이 있는 경우에만 서비스 시작
            val prefs = context.getSharedPreferences(StepCounterService.PREF_NAME, Context.MODE_PRIVATE)
            val lastResetDate = prefs.getString(StepCounterService.KEY_LAST_RESET_DATE, null)
            if (lastResetDate != null) {
                val serviceIntent = Intent(context, StepCounterService::class.java)
                context.startForegroundService(serviceIntent)
            }
        }
    }
}
