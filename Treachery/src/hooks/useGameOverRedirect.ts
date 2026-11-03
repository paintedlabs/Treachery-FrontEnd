import { useEffect } from 'react';
import type { ImperativeRouter } from 'expo-router';

/** Replace the game board with the game-over screen once the game finishes. */
export function useGameOverRedirect(
  isGameFinished: boolean,
  gameId: string,
  router: ImperativeRouter,
): void {
  useEffect(() => {
    if (isGameFinished) {
      router.replace({
        pathname: '/(app)/game-over/[gameId]',
        params: { gameId: gameId! },
      });
    }
  }, [isGameFinished, gameId, router]);
}
