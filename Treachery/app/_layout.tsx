import React, { useEffect } from 'react';
import { Stack, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import { Ionicons } from '@expo/vector-icons';
import { AuthProvider, useAuth } from '@/hooks/useAuth';

function AuthRedirect({ children }: { children: React.ReactNode }) {
  const { authState } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (authState === 'loading') return;

    const inAuthGroup = segments[0] === '(auth)';

    if (authState === 'authenticated' && inAuthGroup) {
      // Signed in but on auth screen — go to app
      router.replace('/(app)');
    } else if (authState === 'unauthenticated' && !inAuthGroup) {
      // Not signed in but on app screen — go to login
      router.replace('/(auth)/login');
    }
  }, [authState, segments]);

  return <>{children}</>;
}

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    ...Ionicons.font,
  });

  if (!fontsLoaded) return null;

  return (
    <AuthProvider>
      <StatusBar style="light" />
      <AuthRedirect>
        <Stack screenOptions={{ headerShown: false }} />
      </AuthRedirect>
    </AuthProvider>
  );
}
