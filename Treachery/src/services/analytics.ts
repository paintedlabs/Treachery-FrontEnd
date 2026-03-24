import { Analytics, getAnalytics, isSupported, logEvent, setUserId, setUserProperties } from 'firebase/analytics';
import { app } from '@/config/firebase';

let analytics: Analytics | null = null;

export async function initAnalytics(): Promise<void> {
  try {
    const supported = await isSupported();
    if (supported) {
      analytics = getAnalytics(app);
    }
  } catch {
    // Analytics not available (SSR, unsupported browser, etc.)
  }
}

export function trackScreen(screenName: string): void {
  if (!analytics) return;
  const eventName: string = 'screen_view';
  logEvent(analytics, eventName, { firebase_screen: screenName });
}

export function trackEvent(name: string, params?: Record<string, string | number>): void {
  if (!analytics) return;
  logEvent(analytics, name, params);
}

export function setAnalyticsUserId(uid: string | null): void {
  if (!analytics) return;
  setUserId(analytics, uid);
}

export function setAnalyticsUserProperties(properties: Record<string, string>): void {
  if (!analytics) return;
  setUserProperties(analytics, properties);
}
