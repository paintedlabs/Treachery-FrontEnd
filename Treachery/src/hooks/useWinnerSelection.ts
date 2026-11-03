import { useState } from 'react';

export interface UseWinnerSelectionReturn {
  isVisible: boolean;
  /** user_ids picked as winners so far. */
  selectedWinners: Set<string>;
  /** Open the picker with nothing selected. */
  open: () => void;
  close: () => void;
  toggleWinner: (userId: string) => void;
  /** Close the picker and end the game with the selected winners (none = no ELO update). */
  confirm: () => void;
}

/** State for the host's End Game winner picker (non-treachery modes). */
export function useWinnerSelection(
  endGame: (winnerUserIds?: string[]) => Promise<void>,
): UseWinnerSelectionReturn {
  const [showWinnerSelection, setShowWinnerSelection] = useState(false);
  const [selectedWinners, setSelectedWinners] = useState<Set<string>>(new Set());

  const handleEndGame = () => {
    setSelectedWinners(new Set());
    setShowWinnerSelection(true);
  };

  const toggleWinner = (userId: string) => {
    setSelectedWinners((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) {
        next.delete(userId);
      } else {
        next.add(userId);
      }
      return next;
    });
  };

  const confirmEndGame = () => {
    setShowWinnerSelection(false);
    const winners = selectedWinners.size > 0 ? Array.from(selectedWinners) : undefined;
    endGame(winners);
  };

  return {
    isVisible: showWinnerSelection,
    selectedWinners,
    open: handleEndGame,
    close: () => setShowWinnerSelection(false),
    toggleWinner,
    confirm: confirmEndGame,
  };
}
