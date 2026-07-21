import Flutter
import UIKit
import google_mobile_ads

class CustomNativeAdFactory: NSObject, FLTNativeAdFactory {
    func createNativeAd(
        _ nativeAd: NativeAd,
        customOptions: [AnyHashable: Any]? = nil
    ) -> NativeAdView? {
        let nativeAdView = NativeAdView()
        nativeAdView.backgroundColor = .white

        // Container
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 15
        container.alignment = .fill
        container.distribution = .fill
        container.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -16),
            container.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
        ])

        // Left: MediaView (150pt width)
        let mediaView = MediaView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        container.addArrangedSubview(mediaView)
        NSLayoutConstraint.activate([
            mediaView.widthAnchor.constraint(equalToConstant: 150),
        ])
        nativeAdView.mediaView = mediaView

        // Right: Content column
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 4
        contentStack.alignment = .fill
        container.addArrangedSubview(contentStack)

        // Title row (headline + ad badge)
        let titleRow = UIView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(titleRow)

        let headlineLabel = UILabel()
        headlineLabel.font = UIFont.boldSystemFont(ofSize: 16)
        headlineLabel.textColor = .black
        headlineLabel.numberOfLines = 1
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.text = nativeAd.headline ?? "광고 제목"
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(headlineLabel)
        nativeAdView.headlineView = headlineLabel

        let adBadge = UILabel()
        adBadge.text = "Ad"
        adBadge.font = UIFont.boldSystemFont(ofSize: 11)
        adBadge.textColor = .white
        adBadge.backgroundColor = UIColor(red: 76/255, green: 175/255, blue: 80/255, alpha: 1)
        adBadge.textAlignment = .center
        adBadge.layer.cornerRadius = 2
        adBadge.clipsToBounds = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(adBadge)

        NSLayoutConstraint.activate([
            titleRow.heightAnchor.constraint(equalToConstant: 20),
            headlineLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            headlineLabel.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            headlineLabel.trailingAnchor.constraint(lessThanOrEqualTo: adBadge.leadingAnchor, constant: -8),
            adBadge.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            adBadge.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            adBadge.widthAnchor.constraint(equalToConstant: 28),
            adBadge.heightAnchor.constraint(equalToConstant: 18),
        ])

        // Advertiser
        let advertiserLabel = UILabel()
        advertiserLabel.font = UIFont.systemFont(ofSize: 13)
        advertiserLabel.textColor = UIColor(red: 102/255, green: 102/255, blue: 102/255, alpha: 1)
        advertiserLabel.numberOfLines = 1
        if let advertiser = nativeAd.advertiser, !advertiser.isEmpty {
            advertiserLabel.text = advertiser
            contentStack.addArrangedSubview(advertiserLabel)
            nativeAdView.advertiserView = advertiserLabel
        }

        // Body
        let bodyLabel = UILabel()
        bodyLabel.font = UIFont.systemFont(ofSize: 14)
        bodyLabel.textColor = UIColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1)
        bodyLabel.numberOfLines = 3
        bodyLabel.lineBreakMode = .byTruncatingTail
        if let body = nativeAd.body, !body.isEmpty {
            bodyLabel.text = body
            contentStack.addArrangedSubview(bodyLabel)
            nativeAdView.bodyView = bodyLabel
        }

        // Spacer
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentStack.addArrangedSubview(spacer)

        // Call to Action Button
        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor(red: 33/255, green: 150/255, blue: 243/255, alpha: 1)
        ctaButton.layer.cornerRadius = 4
        ctaButton.isUserInteractionEnabled = false
        if let cta = nativeAd.callToAction, !cta.isEmpty {
            ctaButton.setTitle(cta, for: .normal)
        } else {
            ctaButton.setTitle("열기", for: .normal)
        }
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(ctaButton)
        NSLayoutConstraint.activate([
            ctaButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        nativeAdView.callToActionView = ctaButton

        nativeAdView.nativeAd = nativeAd

        return nativeAdView
    }
}
