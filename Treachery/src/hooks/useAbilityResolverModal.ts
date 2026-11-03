import { useEffect, useState } from 'react';
import { shouldShowAbilityResolver } from '@/components/AbilityResolver';
import { Player } from '@/models/types';

export interface UseAbilityResolverModalReturn {
  /** The current player holds an unveiled traitor card whose ability still needs resolving. */
  canResolveAbility: boolean;
  /** Whether the AbilityResolver modal should be shown. */
  isVisible: boolean;
  open: () => void;
  close: () => void;
}

/**
 * Visibility of the traitor AbilityResolver modal (Metamorph / Puppet Master /
 * Wearer of Masks), including the one-time auto-open after unveiling.
 */
export function useAbilityResolverModal(
  currentPlayer: Player | null,
): UseAbilityResolverModalReturn {
  const [showAbilityResolver, setShowAbilityResolver] = useState(false);
  const [hasAutoTriggeredAbility, setHasAutoTriggeredAbility] = useState(false);

  const canResolveAbility = shouldShowAbilityResolver(currentPlayer);

  // Auto-open the ability resolver the first time the current player flips to
  // unveiled while holding one of the three traitor cards that need a follow-up.
  useEffect(() => {
    if (canResolveAbility && !hasAutoTriggeredAbility) {
      setShowAbilityResolver(true);
      setHasAutoTriggeredAbility(true);
    }
  }, [canResolveAbility, hasAutoTriggeredAbility]);

  return {
    canResolveAbility,
    isVisible: showAbilityResolver && canResolveAbility,
    open: () => setShowAbilityResolver(true),
    close: () => setShowAbilityResolver(false),
  };
}
