import {
  signInAnonymously,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendPasswordResetEmail,
  signInWithPhoneNumber,
  RecaptchaVerifier,
  ConfirmationResult,
  signOut as firebaseSignOut,
  onAuthStateChanged as firebaseOnAuthStateChanged,
  User,
  Unsubscribe,
} from 'firebase/auth';
import { auth } from '@/config/firebase';

export function signInAsGuest() {
  return signInAnonymously(auth);
}

export function signIn(email: string, password: string) {
  return signInWithEmailAndPassword(auth, email, password);
}

export function signUp(email: string, password: string) {
  return createUserWithEmailAndPassword(auth, email, password);
}

export function resetPassword(email: string) {
  return sendPasswordResetEmail(auth, email);
}

export function signOut() {
  return firebaseSignOut(auth);
}

export function onAuthStateChanged(callback: (user: User | null) => void): Unsubscribe {
  return firebaseOnAuthStateChanged(auth, callback);
}

export function getCurrentUser(): User | null {
  return auth.currentUser;
}

export function createRecaptchaVerifier(containerId: string): RecaptchaVerifier {
  return new RecaptchaVerifier(auth, containerId, { size: 'invisible' });
}

export function sendPhoneCode(
  phoneNumber: string,
  recaptchaVerifier: RecaptchaVerifier,
): Promise<ConfirmationResult> {
  return signInWithPhoneNumber(auth, phoneNumber, recaptchaVerifier);
}

export type { ConfirmationResult, RecaptchaVerifier };
