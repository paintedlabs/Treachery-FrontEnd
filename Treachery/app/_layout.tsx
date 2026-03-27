import React, { useEffect, useRef } from 'react';
import { Stack, useRouter, useSegments, usePathname } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import { Ionicons } from '@expo/vector-icons';
import { AuthProvider, useAuth } from '@/hooks/useAuth';
import { initAnalytics, trackScreen } from '@/services/analytics';

function AuthRedirect({ children }: { children: React.ReactNode }) {
  const { authState, isNewUser } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (authState === 'loading') return;

    const inAuthGroup = segments[0] === '(auth)';
    const inOnboarding = segments.join('/').includes('onboarding');

    if (authState === 'authenticated' && isNewUser && !inOnboarding) {
      // New user — redirect to onboarding
      router.replace('/(app)/onboarding/display-name');
    } else if (authState === 'authenticated' && !isNewUser && inAuthGroup) {
      // Signed in but on auth screen — go to app
      router.replace('/(app)');
    } else if (authState === 'unauthenticated' && !inAuthGroup) {
      // Not signed in but on app screen — go to login
      router.replace('/(auth)/login');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authState, isNewUser, segments]);

  return <>{children}</>;
}

function ScreenTracker() {
  const pathname = usePathname();
  const prevPathname = useRef(pathname);

  useEffect(() => {
    if (pathname !== prevPathname.current) {
      trackScreen(pathname);
      prevPathname.current = pathname;
    }
  }, [pathname]);

  return null;
}

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    ...Ionicons.font,
  });

  useEffect(() => {
    initAnalytics();
  }, []);

  if (!fontsLoaded) return null;

  return (
    <AuthProvider>
      <StatusBar style="light" />
      <ScreenTracker />
      <AuthRedirect>
        <Stack screenOptions={{ headerShown: false }} />
      </AuthRedirect>
    </AuthProvider>
  );
}
