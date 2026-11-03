import { useState } from 'react';
import type { ConfirmDialogProps } from '@/components/ConfirmDialog';
import { ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { IdentityCard, Player } from '@/models/types';

interface UseGameConfirmDialogArgs {
  currentPlayer: Player | null;
  currentIdentityCard: IdentityCard | undefined;
  eliminateAndLeave: () => Promise<void>;
  unveilCurrentPlayer: () => Promise<void>;
}

export interface UseGameConfirmDialogReturn {
  /** Ask the player to confirm unveiling their identity. */
  requestUnveil: () => void;
  /** Ask the player to confirm forfeiting the game. */
  requestForfeit: () => void;
  /** Spread onto the screen's single ConfirmDialog. */
  dialogProps: ConfirmDialogProps;
}

/** State and copy for the game board's Unveil / Forfeit confirmation dialog. */
export function useGameConfirmDialog({
  currentPlayer,
  currentIdentityCard,
  eliminateAndLeave,
  unveilCurrentPlayer,
}: UseGameConfirmDialogArgs): UseGameConfirmDialogReturn {
  // Which confirmation (if any) is showing. In-app ConfirmDialog instead of
  // window.confirm/Alert.alert: one themed code path on every platform, and
  // it stays clickable under automation (Playwright silently cancels native
  // dialogs, which made these buttons appear dead in the playtest harness).
  const [pendingConfirm, setPendingConfirm] = useState<'unveil' | 'forfeit' | null>(null);

  const handleForfeit = () => setPendingConfirm('forfeit');
  const handleUnveil = () => setPendingConfirm('unveil');

  const confirmDialogProps = () => {
    if (pendingConfirm === 'forfeit') {
      return {
        title: 'Forfeit Game?',
        message: 'You will be eliminated from the game. This cannot be undone.',
        confirmLabel: 'Forfeit',
        confirmAccessibilityLabel: 'Confirm forfeit',
        destructive: true,
        onConfirm: async () => {
          setPendingConfirm(null);
          // Stay on the board; navigate only when the game actually finishes.
          await eliminateAndLeave();
        },
      };
    }
    const roleName = currentPlayer?.role ? ROLE_DISPLAY_NAMES[currentPlayer.role] : '';
    const cardName = currentIdentityCard?.name ?? '';
    return {
      title: 'Unveil your identity?',
      message: `This will reveal your role (${roleName}) and card (${cardName}) to all players. This cannot be undone.`,
      confirmLabel: 'Unveil',
      confirmAccessibilityLabel: 'Confirm unveil',
      destructive: false,
      onConfirm: () => {
        setPendingConfirm(null);
        unveilCurrentPlayer();
      },
    };
  };

  return {
    requestUnveil: handleUnveil,
    requestForfeit: handleForfeit,
    dialogProps: {
      visible: pendingConfirm !== null,
      ...confirmDialogProps(),
      onCancel: () => setPendingConfirm(null),
    },
  };
}
