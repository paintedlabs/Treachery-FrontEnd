package com.solomon.treachery.data

import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.analytics.logEvent

object AnalyticsService {
    private var analytics: FirebaseAnalytics? = null

    fun initialize(analytics: FirebaseAnalytics) {
        this.analytics = analytics
    }

    fun trackScreen(screenName: String) {
        analytics?.logEvent(FirebaseAnalytics.Event.SCREEN_VIEW) {
            param(FirebaseAnalytics.Param.SCREEN_NAME, screenName)
        }
    }

    fun trackEvent(eventName: String, params: Map<String, String> = emptyMap()) {
        analytics?.logEvent(eventName) {
            params.forEach { (key, value) ->
                param(key, value)
            }
        }
    }

    fun setUserId(userId: String?) {
        analytics?.setUserId(userId)
    }

    fun setUserProperties(properties: Map<String, String>) {
        properties.forEach { (key, value) ->
            analytics?.setUserProperty(key, value)
        }
    }
}
