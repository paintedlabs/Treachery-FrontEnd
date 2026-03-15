import React from 'react';
import { Redirect } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { LoadingScreen } from '@/components/LoadingScreen';

export default function Index() {
  const { authState } = useAuth();

  if (authState === 'loading') {
    return <LoadingScreen />;
  }

  if (authState === 'authenticated') {
    return <Redirect href="/(app)" />;
  }

  return <Redirect href="/(auth)/login" />;
}
