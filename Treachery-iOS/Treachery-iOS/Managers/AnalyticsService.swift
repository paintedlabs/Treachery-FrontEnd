//
//  AnalyticsService.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/24/26.
//

import FirebaseAnalytics

enum AnalyticsService {

    static func trackScreen(_ screenName: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName
        ])
    }

    static func trackEvent(_ name: String, params: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: params)
    }

    static func setUserId(_ uid: String?) {
        Analytics.setUserID(uid)
    }

    static func setUserProperties(_ properties: [String: String]) {
        for (key, value) in properties {
            Analytics.setUserProperty(value, forName: key)
        }
    }
}
