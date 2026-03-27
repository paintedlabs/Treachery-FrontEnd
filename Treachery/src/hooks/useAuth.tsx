import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { User } from 'firebase/auth';
import { Timestamp } from 'firebase/firestore';
import * as authService from '@/services/auth';
import * as firestoreService from '@/services/firestore';
import { trackEvent, setAnalyticsUserId, setAnalyticsUserProperties } from '@/services/analytics';
import { TreacheryUser } from '@/models/types';

type AuthState = 'loading' | 'authenticated' | 'unauthenticated';

interface AuthContextType {
  authState: AuthState;
  user: User | null;
  currentUserId: string | null;
  errorMessage: string | null;
  isNewUser: boolean;
  signInAsGuest: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  signOut: () => Promise<void>;
  clearError: () => void;
  completeOnboarding: () => void;
  updateDisplayName: (name: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authState, setAuthState] = useState<AuthState>('loading');
  const [user, setUser] = useState<User | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isNewUser, setIsNewUser] = useState(false);

  useEffect(() => {
    const unsubscribe = authService.onAuthStateChanged(async (firebaseUser) => {
      if (firebaseUser) {
        setUser(firebaseUser);
        setAuthState('authenticated');
        setAnalyticsUserId(firebaseUser.uid);
        setAnalyticsUserProperties({
          auth_method: firebaseUser.isAnonymous ? 'guest' : 'email',
        });
        const isNew = await createUserDocumentIfNeeded(firebaseUser);
        if (isNew) setIsNewUser(true);
      } else {
        setUser(null);
        setAuthState('unauthenticated');
        setAnalyticsUserId(null);
      }
    });
    return unsubscribe;
  }, []);

  const createUserDocumentIfNeeded = async (firebaseUser: User): Promise<boolean> => {
    try {
      const existing = await firestoreService.getUser(firebaseUser.uid);
      if (!existing) {
        const newUser: TreacheryUser = {
          id: firebaseUser.uid,
          display_name: firebaseUser.displayName || 'Guest',
          email: firebaseUser.email || null,
          phone_number: firebaseUser.phoneNumber || null,
          friend_ids: [],
          created_at: Timestamp.now(),
        };
        await firestoreService.createUser(newUser);
        return true;
      }
      return false;
    } catch (error) {
      console.warn('Failed to create user document:', error);
      return false;
    }
  };

  const signInAsGuest = useCallback(async () => {
    setErrorMessage(null);
    try {
      const result = await authService.signInAsGuest();
      await createUserDocumentIfNeeded(result.user);
      trackEvent('sign_in', { method: 'guest' });
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to sign in.');
    }
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    setErrorMessage(null);
    try {
      const result = await authService.signIn(email, password);
      await createUserDocumentIfNeeded(result.user);
      trackEvent('sign_in', { method: 'email' });
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to sign in.');
    }
  }, []);

  const signUp = useCallback(async (email: string, password: string) => {
    setErrorMessage(null);
    try {
      const result = await authService.signUp(email, password);
      await createUserDocumentIfNeeded(result.user);
      trackEvent('sign_up', { method: 'email' });
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to create account.');
    }
  }, []);

  const resetPassword = useCallback(async (email: string) => {
    setErrorMessage(null);
    try {
      await authService.resetPassword(email);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to send reset email.');
    }
  }, []);

  const signOut = useCallback(async () => {
    setErrorMessage(null);
    try {
      await authService.signOut();
      trackEvent('sign_out');
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Sign out failed.');
    }
  }, []);

  const clearError = useCallback(() => setErrorMessage(null), []);

  const completeOnboarding = useCallback(() => setIsNewUser(false), []);

  const updateDisplayName = useCallback(async (name: string) => {
    if (!user) return;
    try {
      const existing = await firestoreService.getUser(user.uid);
      if (existing) {
        await firestoreService.updateUser({ ...existing, display_name: name });
      }
    } catch (error) {
      console.warn('Failed to update display name:', error);
    }
  }, [user]);

  return (
    <AuthContext.Provider
      value={{
        authState,
        user,
        currentUserId: user?.uid ?? null,
        errorMessage,
        isNewUser,
        signInAsGuest,
        signIn,
        signUp,
        resetPassword,
        signOut,
        clearError,
        completeOnboarding,
        updateDisplayName,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextType {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
