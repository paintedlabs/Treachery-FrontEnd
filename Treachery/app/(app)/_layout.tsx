import React from 'react';
import { Stack } from 'expo-router';
import { useAuth } from '@/hooks/useAuth';
import { useNotifications } from '@/hooks/useNotifications';
import { colors } from '@/constants/theme';

export default function AppLayout() {
  const { authState } = useAuth();
  useNotifications(authState === 'authenticated');

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.text,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="index" options={{ title: 'Home', headerShown: false }} />
      <Stack.Screen name="create-game" options={{ title: 'Create Game' }} />
      <Stack.Screen name="join-game" options={{ title: 'Join Game' }} />
      <Stack.Screen name="lobby/[gameId]" options={{ title: 'Lobby', headerBackVisible: false }} />
      <Stack.Screen name="game/[gameId]" options={{ title: 'Game', headerBackVisible: false }} />
      <Stack.Screen
        name="game-over/[gameId]"
        options={{ title: 'Results', headerBackVisible: false }}
      />
      <Stack.Screen name="profile" options={{ title: 'Profile' }} />
      <Stack.Screen name="friends" options={{ title: 'Friends' }} />
      <Stack.Screen name="history" options={{ title: 'Game History' }} />
    </Stack>
  );
}
