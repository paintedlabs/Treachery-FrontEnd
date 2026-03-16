import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/config/firebase';

/**
 * Registers the device for push notifications and sends the FCM token
 * to the server. On web, uses the Firebase JS messaging SDK.
 * On native, this is a no-op — iOS handles FCM via the native app delegate.
 *
 * Call this once after the user is authenticated.
 */
export function useNotifications(isAuthenticated: boolean) {
  const hasRegistered = useRef(false);

  useEffect(() => {
    if (!isAuthenticated || hasRegistered.current) return;
    if (Platform.OS !== 'web') return; // Native iOS handles FCM in AppDelegate

    let cancelled = false;

    async function registerWebPush() {
      try {
        // Dynamically import to avoid breaking non-web platforms
        const { getMessaging, getToken } = await import('firebase/messaging');

        const messaging = getMessaging();

        // Request notification permission
        const permission = await Notification.requestPermission();
        if (permission !== 'granted') return;

        // Get FCM token (requires a VAPID key from Firebase Console)
        // If VAPID key isn't configured yet, this will silently fail
        const token = await getToken(messaging, {
          vapidKey: undefined, // Set this from Firebase Console > Cloud Messaging > Web Push certificates
        }).catch(() => null);

        if (!token || cancelled) return;

        // Register token with server
        const registerFn = httpsCallable(functions, 'registerFcmToken');
        await registerFn({ token });
        hasRegistered.current = true;
      } catch {
        // Non-fatal: push notifications are nice-to-have
      }
    }

    registerWebPush();
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated]);
}
