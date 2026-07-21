package com.reviewtube.pigmoney

import android.os.Bundle
import android.util.Log
import android.view.MenuItem
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.LinearLayoutCompat
import androidx.appcompat.widget.Toolbar
import com.pincrux.offerwall.PincruxOfferwall
import com.pincrux.offerwall.ui.common.impl.PincruxCloseImpl

class PincruxViewTypeActivity : AppCompatActivity() {
    private val offerwall: PincruxOfferwall by lazy { PincruxOfferwall.getInstance() }
    private var isPaused = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pincrux_view_type)

        // 툴바 설정
        val toolbar = findViewById<Toolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        supportActionBar?.apply {
            setDisplayHomeAsUpEnabled(true)
            setDisplayShowHomeEnabled(true)
            title = "민트저금통"
        }

        val offerwallContainer = findViewById<LinearLayoutCompat>(R.id.pincrux_offerwall_container)

        try {
            val offerwallView = offerwall.getPincruxOfferwallView(this, object : PincruxCloseImpl {
                override fun onClose() {
                    Log.d(TAG, "onClose")
                    if (!isFinishing) finish()
                }

                override fun onPermissionDenied() {
                    // 충전소 최초 진입시 동의 팝업에서 거부를 선택
                    Log.i(TAG, "onPermissionDenied")
                    if (!isFinishing) finish()
                }

                override fun onAction() {
                    Log.i(TAG, "onAction")
                }
            })

            offerwallView?.let {
                offerwallContainer.addView(it)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Offerwall view 생성 실패", e)
            finish()
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                finish()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isPaused) {
            offerwall.refreshOfferwall()
        }
    }

    override fun onPause() {
        super.onPause()
        isPaused = true
    }

    override fun onDestroy() {
        super.onDestroy()
        offerwall.destroyView()
    }

    companion object {
        private const val TAG = "PincruxViewTypeActivity"
    }
}