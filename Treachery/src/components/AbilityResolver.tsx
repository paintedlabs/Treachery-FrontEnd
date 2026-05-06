import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Modal,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { httpsCallable, FunctionsError } from 'firebase/functions';
import { functions } from '@/config/firebase';
import { Player, IdentityCard } from '@/models/types';
import { getAllCards, getCard } from '@/services/cardDatabase';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, spacing, fonts } from '@/constants/theme';

const METAMORPH_CARD_ID = 'traitor_07';
const PUPPET_MASTER_CARD_ID = 'traitor_09';
const WEARER_OF_MASKS_CARD_ID = 'traitor_13';

type AbilityKind = 'metamorph' | 'puppetMaster' | 'wearerOfMasks';

function abilityFor(card: IdentityCard | undefined | null): AbilityKind | null {
  if (!card) return null;
  if (card.id === METAMORPH_CARD_ID) return 'metamorph';
  if (card.id === PUPPET_MASTER_CARD_ID) return 'puppetMaster';
  if (card.id === WEARER_OF_MASKS_CARD_ID) return 'wearerOfMasks';
  return null;
}

export function shouldShowAbilityResolver(player: Player | undefined | null): boolean {
  if (!player || !player.is_unveiled || !player.identity_card_id) return false;
  return abilityFor(getCard(player.identity_card_id)) !== null;
}

interface Props {
  gameId: string;
  currentPlayer: Player;
  players: Player[];
  visible: boolean;
  onClose: () => void;
}

export function AbilityResolver({ gameId, currentPlayer, players, visible, onClose }: Props) {
  const card = currentPlayer.identity_card_id ? getCard(currentPlayer.identity_card_id) : null;
  const ability = abilityFor(card);

  if (!ability) return null;

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <ScrollView style={styles.sheetScroll} contentContainerStyle={styles.sheetContent}>
          {ability === 'metamorph' && (
            <MetamorphSheet
              gameId={gameId}
              players={players}
              onClose={onClose}
            />
          )}
          {ability === 'puppetMaster' && (
            <PuppetMasterSheet
              gameId={gameId}
              currentPlayerId={currentPlayer.id}
              players={players}
              onClose={onClose}
            />
          )}
          {ability === 'wearerOfMasks' && (
            <WearerOfMasksSheet
              gameId={gameId}
              players={players}
              onClose={onClose}
            />
          )}
        </ScrollView>
      </View>
    </Modal>
  );
}

// ── Metamorph ────────────────────────────────────────────────────

function MetamorphSheet({
  gameId,
  players,
  onClose,
}: {
  gameId: string;
  players: Player[];
  onClose: () => void;
}) {
  const eliminated = players.filter((p) => p.is_eliminated && p.role !== 'leader');
  const [selected, setSelected] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const resolve = async () => {
    if (!selected) return;
    setPending(true);
    setError(null);
    try {
      await httpsCallable(functions, 'resolveMetamorph')({ gameId, targetPlayerId: selected });
      onClose();
    } catch (e) {
      setError((e as FunctionsError)?.message ?? 'Failed to resolve Metamorph.');
      setPending(false);
    }
  };

  return (
    <View style={styles.container}>
      <Ionicons name="swap-horizontal" size={36} color={ROLE_COLORS.traitor} />
      <Text style={styles.title}>The Metamorph</Text>
      <Text style={styles.reminder}>
        {"Steal an eliminated opponent's identity card. Turn it face down if it isn't a Leader."}
      </Text>
      {eliminated.length === 0 ? (
        <View style={styles.emptyBox}>
          <Ionicons name="person-remove-outline" size={28} color={colors.textSecondary} />
          <Text style={styles.emptyText}>No eliminated opponents yet.</Text>
          <Text style={styles.emptyHint}>This ability triggers when an opponent is eliminated.</Text>
        </View>
      ) : (
        eliminated.map((p) => {
          const targetCard = p.identity_card_id ? getCard(p.identity_card_id) : undefined;
          const isSel = selected === p.id;
          return (
            <TouchableOpacity
              key={p.id}
              style={[styles.row, isSel && styles.rowSelected]}
              onPress={() => setSelected(isSel ? null : p.id)}
              accessibilityLabel={`Steal from ${p.display_name}`}
              accessibilityRole="button"
            >
              <View style={{ flex: 1 }}>
                <Text style={[styles.rowName, { textDecorationLine: 'line-through' }]}>{p.display_name}</Text>
                {targetCard && (
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                    <View style={[styles.dot, { backgroundColor: ROLE_COLORS[targetCard.role] }]} />
                    <Text style={[styles.rowRole, { color: ROLE_COLORS[targetCard.role] }]}>{targetCard.name}</Text>
                  </View>
                )}
              </View>
              {isSel && <Ionicons name="checkmark-circle" size={22} color={colors.primary} />}
            </TouchableOpacity>
          );
        })
      )}
      {error && <Text style={styles.errorText}>{error}</Text>}
      {selected && (
        <TouchableOpacity
          style={[styles.primaryBtn, pending && styles.disabled]}
          onPress={resolve}
          disabled={pending}
          accessibilityLabel="Steal identity"
          accessibilityRole="button"
        >
          {pending ? <ActivityIndicator color="#0d0b1a" /> : <Text style={styles.primaryBtnText}>Steal Identity</Text>}
        </TouchableOpacity>
      )}
      <TouchableOpacity
        style={styles.secondaryBtn}
        onPress={onClose}
        disabled={pending}
        accessibilityLabel="Decline ability"
        accessibilityRole="button"
      >
        <Text style={styles.secondaryBtnText}>Decline</Text>
      </TouchableOpacity>
    </View>
  );
}

// ── Puppet Master ────────────────────────────────────────────────

function PuppetMasterSheet({
  gameId,
  currentPlayerId,
  players,
  onClose,
}: {
  gameId: string;
  currentPlayerId: string;
  players: Player[];
  onClose: () => void;
}) {
  const swappable = players.filter((p) => !p.is_eliminated && p.id !== currentPlayerId);
  const initialAssignments = (): Record<string, string> => {
    const map: Record<string, string> = {};
    swappable.forEach((p) => {
      if (p.identity_card_id) map[p.id] = p.identity_card_id;
    });
    return map;
  };
  const [assignments, setAssignments] = useState<Record<string, string>>(initialAssignments);
  const [firstSel, setFirstSel] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleTap = (id: string) => {
    if (firstSel) {
      if (firstSel === id) {
        setFirstSel(null);
        return;
      }
      setAssignments((prev) => {
        const a = prev[firstSel];
        const b = prev[id];
        return { ...prev, [firstSel]: b, [id]: a };
      });
      setFirstSel(null);
    } else {
      setFirstSel(id);
    }
  };

  const swapCount = swappable.filter((p) => assignments[p.id] !== p.identity_card_id).length;

  const resolve = async () => {
    setPending(true);
    setError(null);
    try {
      await httpsCallable(functions, 'resolvePuppetMaster')({ gameId, redistributions: assignments });
      onClose();
    } catch (e) {
      setError((e as FunctionsError)?.message ?? 'Failed to resolve Puppet Master.');
      setPending(false);
    }
  };

  return (
    <View style={styles.container}>
      <Ionicons name="repeat" size={36} color={ROLE_COLORS.traitor} />
      <Text style={styles.title}>The Puppet Master</Text>
      <Text style={styles.reminder}>
        Redistribute identity cards among other players. Non-Leader cards are turned face down.
      </Text>
      <View style={styles.instructionBox}>
        <Ionicons name={firstSel ? 'hand-right' : 'hand-left'} size={16} color={colors.primary} />
        <Text style={styles.instructionText}>
          {firstSel ? 'Now tap another player to swap with' : "Tap a player's card to select it for swapping"}
        </Text>
      </View>
      {swappable.map((p) => {
        const cardId = assignments[p.id];
        const c = cardId ? getCard(cardId) : undefined;
        const wasSwapped = cardId !== p.identity_card_id;
        const isSel = firstSel === p.id;
        return (
          <TouchableOpacity
            key={p.id}
            style={[styles.row, isSel && styles.rowSelected, wasSwapped && styles.rowSwapped]}
            onPress={() => handleTap(p.id)}
            accessibilityLabel={`Swap with ${p.display_name}`}
            accessibilityRole="button"
          >
            <View style={{ flex: 1 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <Text style={styles.rowName}>{p.display_name}</Text>
                {wasSwapped && (
                  <View style={styles.swapBadge}>
                    <Text style={styles.swapBadgeText}>SWAPPED</Text>
                  </View>
                )}
              </View>
              {c && (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                  <View style={[styles.dot, { backgroundColor: ROLE_COLORS[c.role] }]} />
                  <Text style={[styles.rowRole, { color: ROLE_COLORS[c.role] }]}>{c.name}</Text>
                </View>
              )}
            </View>
            <Ionicons
              name={isSel ? 'swap-horizontal-outline' : 'swap-horizontal'}
              size={18}
              color={isSel ? colors.primary : colors.textSecondary}
            />
          </TouchableOpacity>
        );
      })}
      {error && <Text style={styles.errorText}>{error}</Text>}
      {swapCount > 0 ? (
        <TouchableOpacity
          style={[styles.primaryBtn, pending && styles.disabled]}
          onPress={resolve}
          disabled={pending}
          accessibilityLabel="Confirm redistribution"
          accessibilityRole="button"
        >
          {pending ? <ActivityIndicator color="#0d0b1a" /> : <Text style={styles.primaryBtnText}>Confirm Redistribution</Text>}
        </TouchableOpacity>
      ) : null}
      <TouchableOpacity
        style={styles.secondaryBtn}
        onPress={onClose}
        disabled={pending}
        accessibilityLabel="Decline ability"
        accessibilityRole="button"
      >
        <Text style={styles.secondaryBtnText}>Decline</Text>
      </TouchableOpacity>
    </View>
  );
}

// ── Wearer of Masks ──────────────────────────────────────────────

function WearerOfMasksSheet({
  gameId,
  players,
  onClose,
}: {
  gameId: string;
  players: Player[];
  onClose: () => void;
}) {
  const [xValue, setXValue] = useState(3);
  const [revealed, setRevealed] = useState<IdentityCard[]>([]);
  const [hasRevealed, setHasRevealed] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const usedIds = new Set(players.map((p) => p.identity_card_id).filter(Boolean));

  const doReveal = () => {
    const available = getAllCards().filter((c) => c.role !== 'leader' && !usedIds.has(c.id));
    const shuffled = [...available].sort(() => Math.random() - 0.5);
    setRevealed(shuffled.slice(0, Math.min(xValue, shuffled.length)));
    setHasRevealed(true);
  };

  const resolve = async (cardId: string | null) => {
    setPending(true);
    setError(null);
    try {
      await httpsCallable(functions, 'resolveWearerOfMasks')({ gameId, chosenCardId: cardId });
      onClose();
    } catch (e) {
      setError((e as FunctionsError)?.message ?? 'Failed to resolve Wearer of Masks.');
      setPending(false);
    }
  };

  return (
    <View style={styles.container}>
      <Ionicons name="eye-outline" size={36} color={ROLE_COLORS.traitor} />
      <Text style={styles.title}>The Wearer of Masks</Text>
      <Text style={styles.reminder}>
        Reveal up to X non-Leader identity cards at random from outside the game. Choose one to become.
      </Text>
      {!hasRevealed ? (
        <>
          <Text style={styles.xLabel}>How much mana did you pay for X?</Text>
          <View style={styles.xRow}>
            <TouchableOpacity
              onPress={() => setXValue(Math.max(1, xValue - 1))}
              accessibilityLabel="Decrease X"
              accessibilityRole="button"
            >
              <Ionicons name="remove-circle" size={36} color={colors.error} />
            </TouchableOpacity>
            <Text style={styles.xValue} accessibilityLabel={`X is ${xValue}`}>{xValue}</Text>
            <TouchableOpacity
              onPress={() => setXValue(xValue + 1)}
              accessibilityLabel="Increase X"
              accessibilityRole="button"
            >
              <Ionicons name="add-circle" size={36} color={colors.success} />
            </TouchableOpacity>
          </View>
          <TouchableOpacity
            style={styles.primaryBtn}
            onPress={doReveal}
            accessibilityLabel="Reveal cards"
            accessibilityRole="button"
          >
            <Text style={styles.primaryBtnText}>Reveal Cards</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.secondaryBtn}
            onPress={() => resolve(null)}
            accessibilityLabel="Skip ability"
            accessibilityRole="button"
          >
            <Text style={styles.secondaryBtnText}>Skip</Text>
          </TouchableOpacity>
        </>
      ) : (
        <>
          <Text style={[styles.xLabel, { color: colors.primary }]}>Choose an Identity</Text>
          {revealed.length === 0 ? (
            <Text style={styles.emptyText}>No eligible cards outside the game.</Text>
          ) : (
            revealed.map((c) => {
              const isSel = selected === c.id;
              return (
                <TouchableOpacity
                  key={c.id}
                  style={[styles.row, isSel && styles.rowSelected]}
                  onPress={() => setSelected(isSel ? null : c.id)}
                  accessibilityLabel={`Pick identity ${c.name}`}
                  accessibilityRole="button"
                >
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                      <View style={[styles.dot, { backgroundColor: ROLE_COLORS[c.role] }]} />
                      <Text style={styles.rowName}>{c.name}</Text>
                      <Text style={[styles.rowRole, { color: ROLE_COLORS[c.role] }]}>
                        {ROLE_DISPLAY_NAMES[c.role]}
                      </Text>
                    </View>
                  </View>
                  {isSel && <Ionicons name="checkmark-circle" size={22} color={colors.primary} />}
                </TouchableOpacity>
              );
            })
          )}
          {error && <Text style={styles.errorText}>{error}</Text>}
          {selected && (
            <TouchableOpacity
              style={[styles.primaryBtn, pending && styles.disabled]}
              onPress={() => resolve(selected)}
              disabled={pending}
              accessibilityLabel="Become this identity"
              accessibilityRole="button"
            >
              {pending ? <ActivityIndicator color="#0d0b1a" /> : <Text style={styles.primaryBtnText}>Become This Identity</Text>}
            </TouchableOpacity>
          )}
          <TouchableOpacity
            style={styles.secondaryBtn}
            onPress={() => resolve(null)}
            disabled={pending}
            accessibilityLabel="Decline ability"
            accessibilityRole="button"
          >
            <Text style={styles.secondaryBtnText}>Decline</Text>
          </TouchableOpacity>
        </>
      )}
    </View>
  );
}

// ── Styles ───────────────────────────────────────────────────────

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'flex-end',
  },
  sheetScroll: {
    maxHeight: '85%',
    backgroundColor: colors.background,
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
  },
  sheetContent: { padding: spacing.lg },
  container: { gap: spacing.md, alignItems: 'center' },
  title: { color: colors.text, fontSize: 20, fontWeight: 'bold', fontFamily: fonts.serif },
  reminder: { color: colors.textSecondary, fontSize: 12, textAlign: 'center', lineHeight: 18, paddingHorizontal: spacing.md },
  emptyBox: {
    alignItems: 'center', gap: 8, padding: spacing.xl,
    backgroundColor: colors.surface, borderRadius: 12, borderWidth: 1, borderColor: colors.divider, width: '100%',
  },
  emptyText: { color: colors.text, fontSize: 14, fontWeight: '500' },
  emptyHint: { color: colors.textSecondary, fontSize: 12, textAlign: 'center' },
  errorText: { color: colors.error, fontSize: 12, textAlign: 'center' },
  row: {
    width: '100%', padding: spacing.md, backgroundColor: colors.surface, borderRadius: 8,
    borderWidth: 1, borderColor: colors.divider, flexDirection: 'row', alignItems: 'center', gap: 8,
  },
  rowSelected: { backgroundColor: ROLE_COLORS.traitor + '20', borderColor: ROLE_COLORS.traitor },
  rowSwapped: { borderColor: ROLE_COLORS.traitor + '60' },
  rowName: { color: colors.text, fontSize: 14, fontWeight: '600' },
  rowRole: { fontSize: 12, fontWeight: '500' },
  dot: { width: 8, height: 8, borderRadius: 4 },
  primaryBtn: { backgroundColor: colors.primary, borderRadius: 8, paddingVertical: 14, width: '100%', alignItems: 'center' },
  primaryBtnText: { color: '#0d0b1a', fontSize: 15, fontWeight: '700' },
  secondaryBtn: { borderRadius: 8, paddingVertical: 12, width: '100%', alignItems: 'center', borderWidth: 1, borderColor: colors.primary },
  secondaryBtnText: { color: colors.primary, fontSize: 14, fontWeight: '600' },
  disabled: { opacity: 0.5 },
  xLabel: { color: colors.text, fontSize: 14, fontWeight: '500' },
  xRow: { flexDirection: 'row', alignItems: 'center', gap: 20 },
  xValue: { color: colors.primary, fontSize: 48, fontWeight: 'bold', fontFamily: fonts.serif, minWidth: 60, textAlign: 'center' },
  instructionBox: {
    flexDirection: 'row', alignItems: 'center', gap: 6, padding: spacing.sm,
    backgroundColor: colors.surfaceLight, borderRadius: 8, width: '100%', justifyContent: 'center',
  },
  instructionText: { color: colors.text, fontSize: 12, fontWeight: '500' },
  swapBadge: {
    backgroundColor: ROLE_COLORS.traitor + '30',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  swapBadgeText: { color: ROLE_COLORS.traitor, fontSize: 9, fontWeight: '700' },
});
