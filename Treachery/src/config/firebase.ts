import { initializeApp } from 'firebase/app';
import { getAuth, connectAuthEmulator } from 'firebase/auth';
import { collection, getDocs, getFirestore, connectFirestoreEmulator } from 'firebase/firestore';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';

const useEmulator = process.env.EXPO_PUBLIC_USE_EMULATOR === 'true';

const firebaseConfig = useEmulator
  ? { projectId: 'demo-test', apiKey: 'demo', appId: 'demo' }
  : {
      apiKey: process.env.EXPO_PUBLIC_FIREBASE_API_KEY,
      authDomain: process.env.EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN,
      projectId: process.env.EXPO_PUBLIC_FIREBASE_PROJECT_ID,
      storageBucket: process.env.EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET,
      messagingSenderId: process.env.EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
      appId: process.env.EXPO_PUBLIC_FIREBASE_APP_ID,
    };

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app);

if (useEmulator) {
  connectAuthEmulator(auth, 'http://localhost:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, 'localhost', 8087);
  connectFunctionsEmulator(functions, 'localhost', 5001);

  // Emulator-only test helpers exposed on window for Playwright E2E.
  // The emulator-mode bundle is a separate build (build:web:emulator),
  // so this branch is dead-code-eliminated from production exports.
  if (typeof window !== 'undefined') {
    (window as unknown as { __e2e?: Record<string, unknown> }).__e2e = {
      startGameWithSeed: (gameId: string, testSeed: unknown) =>
        httpsCallable(functions, 'startGame')({ gameId, testSeed }),
      getCurrentUserId: () => auth.currentUser?.uid ?? null,
      // Reads /games/{gameId}/players. Firestore rules require the caller
      // to be in the game's player_ids — fine for E2E since the test always
      // calls this from a player's authenticated browser context.
      fetchPlayers: async (gameId: string) => {
        const snap = await getDocs(collection(db, `games/${gameId}/players`));
        return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
      },
    };
  }
}
