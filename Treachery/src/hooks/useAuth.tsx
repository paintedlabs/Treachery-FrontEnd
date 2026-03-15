import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { User } from 'firebase/auth';
import { Timestamp } from 'firebase/firestore';
import * as authService from '@/services/auth';
import * as firestoreService from '@/services/firestore';
import { TreacheryUser } from '@/models/types';

type AuthState = 'loading' | 'authenticated' | 'unauthenticated';

interface AuthContextType {
  authState: AuthState;
  user: User | null;
  currentUserId: string | null;
  errorMessage: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authState, setAuthState] = useState<AuthState>('loading');
  const [user, setUser] = useState<User | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribe = authService.onAuthStateChanged(async (firebaseUser) => {
      if (firebaseUser) {
        setUser(firebaseUser);
        setAuthState('authenticated');
        await createUserDocumentIfNeeded(firebaseUser);
      } else {
        setUser(null);
        setAuthState('unauthenticated');
      }
    });
    return unsubscribe;
  }, []);

  const createUserDocumentIfNeeded = async (firebaseUser: User) => {
    try {
      const existing = await firestoreService.getUser(firebaseUser.uid);
      if (!existing) {
        const newUser: TreacheryUser = {
          id: firebaseUser.uid,
          display_name: firebaseUser.displayName || firebaseUser.phoneNumber || 'Player',
          email: firebaseUser.email || null,
          phone_number: firebaseUser.phoneNumber || null,
          friend_ids: [],
          created_at: Timestamp.now(),
        };
        await firestoreService.createUser(newUser);
      }
    } catch (error) {
      console.warn('Failed to create user document:', error);
    }
  };

  const signIn = useCallback(async (email: string, password: string) => {
    setErrorMessage(null);
    try {
      await authService.signIn(email, password);
    } catch (error: any) {
      setErrorMessage(error.message || 'Sign in failed.');
    }
  }, []);

  const signUp = useCallback(async (email: string, password: string) => {
    setErrorMessage(null);
    try {
      const result = await authService.signUp(email, password);
      await createUserDocumentIfNeeded(result.user);
    } catch (error: any) {
      setErrorMessage(error.message || 'Sign up failed.');
    }
  }, []);

  const signOut = useCallback(async () => {
    setErrorMessage(null);
    try {
      await authService.signOut();
    } catch (error: any) {
      setErrorMessage(error.message || 'Sign out failed.');
    }
  }, []);

  const resetPassword = useCallback(async (email: string) => {
    setErrorMessage(null);
    try {
      await authService.resetPassword(email);
    } catch (error: any) {
      setErrorMessage(error.message || 'Password reset failed.');
    }
  }, []);

  const clearError = useCallback(() => setErrorMessage(null), []);

  return (
    <AuthContext.Provider
      value={{
        authState,
        user,
        currentUserId: user?.uid ?? null,
        errorMessage,
        signIn,
        signUp,
        signOut,
        resetPassword,
        clearError,
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
