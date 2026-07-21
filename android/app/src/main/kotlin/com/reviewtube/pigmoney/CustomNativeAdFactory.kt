package com.reviewtube.pigmoney

import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import com.google.android.gms.ads.nativead.MediaView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class CustomNativeAdFactory(private val layoutInflater: LayoutInflater) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        Log.d("CustomNativeAdFactory", "Creating custom native ad view")

        // 커스텀 레이아웃 inflate
        val adView = layoutInflater.inflate(R.layout.custom_native_ad_200, null) as NativeAdView

        // MediaView 설정
        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        adView.mediaView = mediaView
        Log.d("CustomNativeAdFactory", "MediaView set")

        // Headline 설정
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline ?: "광고 제목"
        adView.headlineView = headlineView
        Log.d("CustomNativeAdFactory", "Headline: ${nativeAd.headline}")

        // Body 설정
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        if (nativeAd.body != null && nativeAd.body!!.isNotEmpty()) {
            bodyView.text = nativeAd.body
            bodyView.visibility = View.VISIBLE
            adView.bodyView = bodyView
            Log.d("CustomNativeAdFactory", "Body: ${nativeAd.body}")
        } else {
            bodyView.visibility = View.GONE
        }

        // Advertiser 설정
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        if (nativeAd.advertiser != null && nativeAd.advertiser!!.isNotEmpty()) {
            advertiserView.text = nativeAd.advertiser
            advertiserView.visibility = View.VISIBLE
            adView.advertiserView = advertiserView
            Log.d("CustomNativeAdFactory", "Advertiser: ${nativeAd.advertiser}")
        } else {
            advertiserView.visibility = View.GONE
        }

        // Call to Action 버튼 설정
        val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)
        if (nativeAd.callToAction != null && nativeAd.callToAction!!.isNotEmpty()) {
            ctaView.text = nativeAd.callToAction
            ctaView.visibility = View.VISIBLE
            adView.callToActionView = ctaView
            Log.d("CustomNativeAdFactory", "CTA: ${nativeAd.callToAction}")
        } else {
            ctaView.visibility = View.GONE
        }

        // NativeAd 객체를 NativeAdView에 설정
        adView.setNativeAd(nativeAd)

        Log.d("CustomNativeAdFactory", "Custom native ad view created successfully")

        return adView
    }
}
