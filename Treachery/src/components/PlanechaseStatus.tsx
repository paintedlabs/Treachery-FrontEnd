import React from 'react';
import { PlaneCardBanner } from '@/components/PlaneCardBanner';
import { ChaoticAetherBanner } from '@/components/ChaoticAetherBanner';
import { PhenomenonOverlay } from '@/components/PhenomenonOverlay';
import { PlaneCard } from '@/models/types';

interface PlanechaseStatusProps {
  isPlanechaseActive: boolean;
  isOwnDeckMode: boolean;
  currentPlane: PlaneCard | undefined;
  secondaryPlane: PlaneCard | undefined;
  onPressPlane: () => void;
  dieRollCost: number;
  isRollingDie: boolean;
  /** Omit to hide the roll control (e.g. for eliminated spectators). */
  onRollDie: (() => void) | undefined;
  dieRollResult: string | null;
  lastRollerName: string | null;
  isChaoticAetherActive: boolean;
  /** A phenomenon is waiting to be resolved by this (non-spectator) player. */
  showPhenomenonResolver: boolean;
  isPending: boolean;
  onResolvePhenomenon: () => void;
}

/**
 * The game board's Planechase status stack: current plane banner (with die
 * controls), Chaotic Aether notice, and the phenomenon resolver. Renders
 * nothing outside Planechase games.
 */
export function PlanechaseStatus({
  isPlanechaseActive,
  isOwnDeckMode,
  currentPlane,
  secondaryPlane,
  onPressPlane,
  dieRollCost,
  isRollingDie,
  onRollDie,
  dieRollResult,
  lastRollerName,
  isChaoticAetherActive,
  showPhenomenonResolver,
  isPending,
  onResolvePhenomenon,
}: PlanechaseStatusProps) {
  return (
    <>
      {isPlanechaseActive && !isOwnDeckMode && currentPlane && (
        <PlaneCardBanner
          planeCard={currentPlane}
          secondaryPlaneCard={secondaryPlane}
          onPress={onPressPlane}
          dieCost={dieRollCost}
          isRolling={isRollingDie}
          onRollDie={onRollDie}
          lastDieResult={dieRollResult}
          lastRollerName={lastRollerName}
        />
      )}

      {isPlanechaseActive && isChaoticAetherActive && <ChaoticAetherBanner />}

      {showPhenomenonResolver && currentPlane && (
        <PhenomenonOverlay
          plane={currentPlane}
          isPending={isPending}
          onResolve={onResolvePhenomenon}
        />
      )}
    </>
  );
}
