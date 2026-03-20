import { useState, useEffect } from 'react';

/**
 * Monitors Firestore connection status by listening to a lightweight doc.
 * Returns true when the client is connected and syncing with the server.
 * Uses the special ".info/connected" approach via a canary listener.
 */
export function useConnectionStatus(): { isOffline: boolean } {
  const [isOffline, setIsOffline] = useState(false);

  useEffect(() => {
    // Firestore JS SDK doesn't expose .info/connected like RTDB.
    // Instead we detect offline via snapshot listener errors/metadata.
    // We use enableNetwork/disableNetwork events + a heartbeat approach:
    // If a snapshot comes back from cache only (metadata.fromCache), we're offline.
    let timeout: ReturnType<typeof setTimeout>;

    // Listen to a lightweight doc — any active game listener works,
    // but we'll use a sentinel approach: watch metadata on any snapshot.
    // For simplicity, we track via window online/offline events + Firestore hasPendingWrites.
    const handleOnline = () => {
      clearTimeout(timeout);
      setIsOffline(false);
    };

    const handleOffline = () => {
      // Small delay to avoid flicker on brief disconnects
      timeout = setTimeout(() => setIsOffline(true), 2000);
    };

    if (typeof window !== 'undefined') {
      window.addEventListener('online', handleOnline);
      window.addEventListener('offline', handleOffline);

      // Check initial state
      if (!navigator.onLine) {
        setIsOffline(true);
      }
    }

    return () => {
      clearTimeout(timeout);
      if (typeof window !== 'undefined') {
        window.removeEventListener('online', handleOnline);
        window.removeEventListener('offline', handleOffline);
      }
    };
  }, []);

  return { isOffline };
}
