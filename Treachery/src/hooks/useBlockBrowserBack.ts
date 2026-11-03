import { useEffect } from 'react';
import { Platform } from 'react-native';

/**
 * On web, intercept the browser back button so it keeps the user on the
 * current page: a duplicate history entry is pushed on mount and re-pushed on
 * every popstate. No-op on native.
 */
export function useBlockBrowserBack(): void {
  useEffect(() => {
    if (Platform.OS !== 'web') return;

    // Push a duplicate history entry so pressing back stays on this page
    window.history.pushState(null, '', window.location.href);

    const handlePopState = () => {
      // Re-push so the user can't back out
      window.history.pushState(null, '', window.location.href);
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);
}
