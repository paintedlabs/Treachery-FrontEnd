import React, { useState, useMemo, useCallback } from 'react';
import { View, Text, TouchableOpacity, ScrollView, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Timestamp } from 'firebase/firestore';
import { Player, IdentityCard } from '@/models/types';
import { getAllCards, getCard } from '@/services/cardDatabase';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, spacing, fonts } from '@/constants/theme';

type AbilityType = 'metamorph' | 'puppetMaster' | 'wearerOfMasks';

const ABILITY_CARD_IDS: Record<AbilityType, string> = {
  metamorph: 'traitor_07',
  puppetMaster: 'traitor_09',
  wearerOfMasks: 'traitor_13',
};

const ABILITY_NAMES: Record<AbilityType, string> = {
  metamorph: 'The Metamorph',
  puppetMaster: 'The Puppet Master',
  wearerOfMasks: 'The Wearer of Masks',
};

function buildMockPlayers(abilityType: AbilityType): Player[] {
  const allCards = getAllCards();
  const leaderCard = allCards.find((c) => c.role === 'leader');
  const guardianCard = allCards.find((c) => c.role === 'guardian');
  const assassinCard1 = allCards.find((c) => c.role === 'assassin');
  const assassinCards = allCards.filter((c) => c.role === 'assassin');
  const assassinCard2 = assassinCards.length > 1 ? assassinCards[1] : assassinCards[0];

  return [
    {
      id: 'p1', order_id: 0, user_id: 'dev_leader', display_name: 'Aragorn',
      role: 'leader', identity_card_id: leaderCard?.id ?? null,
      life_total: 45, is_eliminated: false, is_unveiled: false,
      joined_at: Timestamp.now(), player_color: null, commander_name: null, is_ready: false,
    },
    {
      id: 'p2', order_id: 1, user_id: 'dev_guardian', display_name: 'Gandalf',
      role: 'guardian', identity_card_id: guardianCard?.id ?? null,
      life_total: 40, is_eliminated: false, is_unveiled: false,
      joined_at: Timestamp.now(), player_color: null, commander_name: null, is_ready: false,
    },
    {
      id: 'p3', order_id: 2, user_id: 'dev_assassin1', display_name: 'Sauron',
      role: 'assassin', identity_card_id: assassinCard1?.id ?? null,
      life_total: 35, is_eliminated: false, is_unveiled: true,
      joined_at: Timestamp.now(), player_color: null, commander_name: null, is_ready: false,
    },
    {
      id: 'p4', order_id: 3, user_id: 'dev_user', display_name: 'You (Traitor)',
      role: 'traitor', identity_card_id: ABILITY_CARD_IDS[abilityType],
      life_total: 40, is_eliminated: false, is_unveiled: true,
      joined_at: Timestamp.now(), player_color: null, commander_name: null, is_ready: false,
    },
    {
      id: 'p5', order_id: 4, user_id: 'dev_assassin2', display_name: 'Saruman',
      role: 'assassin', identity_card_id: assassinCard2?.id ?? null,
      life_total: 0, is_eliminated: true, is_unveiled: true,
      joined_at: Timestamp.now(), player_color: null, commander_name: null, is_ready: false,
    },
  ];
}

// ── Metamorph Sheet ──────────────────────────────────────────────

function MetamorphSheet({ players, onResolve, onDismiss }: {
  players: Player[];
  onResolve: (targetId: string) => void;
  onDismiss: () => void;
}) {
  const eliminated = players.filter((p) => p.is_eliminated && p.role !== 'leader');
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <View style={sheetStyles.container}>
      <Ionicons name="swap-horizontal" size={36} color={ROLE_COLORS.traitor} />
      <Text style={sheetStyles.title}>The Metamorph</Text>
      <Text style={sheetStyles.reminder}>
        {"Steal an eliminated opponent's identity card. Turn it face down if it isn't a Leader."}
      </Text>
      {eliminated.length === 0 ? (
        <View style={sheetStyles.emptyBox}>
          <Ionicons name="person-remove-outline" size={28} color={colors.textSecondary} />
          <Text style={sheetStyles.emptyText}>No eliminated opponents yet.</Text>
          <Text style={sheetStyles.emptyHint}>This ability triggers when an opponent is eliminated this turn.</Text>
        </View>
      ) : (
        eliminated.map((p) => {
          const card = p.identity_card_id ? getCard(p.identity_card_id) : undefined;
          const isSel = selected === p.id;
          return (
            <TouchableOpacity
              key={p.id}
              style={[sheetStyles.row, isSel && sheetStyles.rowSelected]}
              onPress={() => setSelected(isSel ? null : p.id)}
            >
              <View style={{ flex: 1 }}>
                <Text style={[sheetStyles.rowName, { textDecorationLine: 'line-through' }]}>{p.display_name}</Text>
                {card && (
                  <>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                      <View style={[sheetStyles.dot, { backgroundColor: ROLE_COLORS[card.role] }]} />
                      <Text style={[sheetStyles.rowRole, { color: ROLE_COLORS[card.role] }]}>{card.name}</Text>
                    </View>
                    <Text style={sheetStyles.rowAbility} numberOfLines={2}>{card.ability_text}</Text>
                  </>
                )}
              </View>
              {isSel && <Ionicons name="checkmark-circle" size={22} color={colors.primary} />}
            </TouchableOpacity>
          );
        })
      )}
      {selected && (
        <TouchableOpacity style={sheetStyles.primaryBtn} onPress={() => onResolve(selected)}>
          <Text style={sheetStyles.primaryBtnText}>Steal Identity</Text>
        </TouchableOpacity>
      )}
      <TouchableOpacity style={sheetStyles.secondaryBtn} onPress={onDismiss}>
        <Text style={sheetStyles.secondaryBtnText}>Decline</Text>
      </TouchableOpacity>
    </View>
  );
}

// ── Puppet Master Sheet ──────────────────────────────────────────

function PuppetMasterSheet({ players, onResolve, onDismiss }: {
  players: Player[];
  onResolve: (assignments: Record<string, string>) => void;
  onDismiss: () => void;
}) {
  const swappable = players.filter((p) => !p.is_eliminated && p.user_id !== 'dev_user');
  const [assignments, setAssignments] = useState<Record<string, string>>(() => {
    const map: Record<string, string> = {};
    swappable.forEach((p) => { if (p.identity_card_id) map[p.id] = p.identity_card_id; });
    return map;
  });
  const [firstSel, setFirstSel] = useState<string | null>(null);

  const handleTap = (id: string) => {
    if (firstSel) {
      if (firstSel === id) { setFirstSel(null); return; }
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

  return (
    <View style={sheetStyles.container}>
      <Ionicons name="repeat" size={36} color={ROLE_COLORS.traitor} />
      <Text style={sheetStyles.title}>The Puppet Master</Text>
      <Text style={sheetStyles.reminder}>
        Redistribute identity cards among other players. Non-Leader cards are turned face down.
      </Text>
      <View style={sheetStyles.instructionBox}>
        <Ionicons name={firstSel ? 'hand-right' : 'hand-left'} size={16} color={colors.primary} />
        <Text style={sheetStyles.instructionText}>
          {firstSel ? 'Now tap another player to swap with' : 'Tap a player\'s card to select it for swapping'}
        </Text>
      </View>
      {swappable.map((p) => {
        const cardId = assignments[p.id];
        const card = cardId ? getCard(cardId) : undefined;
        const wasSwapped = cardId !== p.identity_card_id;
        const isSel = firstSel === p.id;
        return (
          <TouchableOpacity
            key={p.id}
            style={[sheetStyles.row, isSel && sheetStyles.rowSelected, wasSwapped && sheetStyles.rowSwapped]}
            onPress={() => handleTap(p.id)}
          >
            <View style={{ flex: 1 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <Text style={sheetStyles.rowName}>{p.display_name}</Text>
                {wasSwapped && (
                  <View style={sheetStyles.swapBadge}>
                    <Text style={sheetStyles.swapBadgeText}>SWAPPED</Text>
                  </View>
                )}
              </View>
              {card && (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 2 }}>
                  <View style={[sheetStyles.dot, { backgroundColor: ROLE_COLORS[card.role] }]} />
                  <Text style={[sheetStyles.rowRole, { color: ROLE_COLORS[card.role] }]}>{card.name}</Text>
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
      {swapCount > 0 && (
        <>
          <TouchableOpacity style={sheetStyles.primaryBtn} onPress={() => onResolve(assignments)}>
            <Text style={sheetStyles.primaryBtnText}>Confirm Redistribution</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={sheetStyles.secondaryBtn}
            onPress={() => {
              const reset: Record<string, string> = {};
              swappable.forEach((p) => { if (p.identity_card_id) reset[p.id] = p.identity_card_id; });
              setAssignments(reset);
              setFirstSel(null);
            }}
          >
            <Text style={sheetStyles.secondaryBtnText}>Undo All Swaps</Text>
          </TouchableOpacity>
        </>
      )}
      <TouchableOpacity style={sheetStyles.secondaryBtn} onPress={onDismiss}>
        <Text style={sheetStyles.secondaryBtnText}>Decline</Text>
      </TouchableOpacity>
    </View>
  );
}

// ── Wearer of Masks Sheet ────────────────────────────────────────

function WearerOfMasksSheet({ players, onResolve, onDismiss }: {
  players: Player[];
  onResolve: (cardId: string | null) => void;
  onDismiss: () => void;
}) {
  const [xValue, setXValue] = useState(3);
  const [revealed, setRevealed] = useState<IdentityCard[]>([]);
  const [hasRevealed, setHasRevealed] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  const usedIds = new Set(players.map((p) => p.identity_card_id).filter(Boolean));

  const doReveal = () => {
    const available = getAllCards().filter((c) => c.role !== 'leader' && !usedIds.has(c.id));
    const shuffled = [...available].sort(() => Math.random() - 0.5);
    setRevealed(shuffled.slice(0, Math.min(xValue, shuffled.length)));
    setHasRevealed(true);
  };

  return (
    <View style={sheetStyles.container}>
      <Ionicons name="eye-outline" size={36} color={ROLE_COLORS.traitor} />
      <Text style={sheetStyles.title}>The Wearer of Masks</Text>
      <Text style={sheetStyles.reminder}>
        Reveal up to X non-Leader identity cards at random from outside the game. Choose one to become.
      </Text>
      {!hasRevealed ? (
        <>
          <Text style={sheetStyles.xLabel}>How much mana did you pay for X?</Text>
          <View style={sheetStyles.xRow}>
            <TouchableOpacity onPress={() => setXValue(Math.max(1, xValue - 1))}>
              <Ionicons name="remove-circle" size={36} color={colors.error} />
            </TouchableOpacity>
            <Text style={sheetStyles.xValue}>{xValue}</Text>
            <TouchableOpacity onPress={() => setXValue(xValue + 1)}>
              <Ionicons name="add-circle" size={36} color={colors.success} />
            </TouchableOpacity>
          </View>
          <TouchableOpacity style={sheetStyles.primaryBtn} onPress={doReveal}>
            <Text style={sheetStyles.primaryBtnText}>Reveal Cards</Text>
          </TouchableOpacity>
        </>
      ) : (
        <>
          <Text style={[sheetStyles.xLabel, { color: colors.primary }]}>Choose an Identity</Text>
          {revealed.length === 0 ? (
            <Text style={sheetStyles.emptyText}>No eligible cards outside the game.</Text>
          ) : (
            revealed.map((card) => {
              const isSel = selected === card.id;
              return (
                <TouchableOpacity
                  key={card.id}
                  style={[sheetStyles.row, isSel && sheetStyles.rowSelected]}
                  onPress={() => setSelected(isSel ? null : card.id)}
                >
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                      <View style={[sheetStyles.dot, { backgroundColor: ROLE_COLORS[card.role] }]} />
                      <Text style={sheetStyles.rowName}>{card.name}</Text>
                      <Text style={[sheetStyles.rowRole, { color: ROLE_COLORS[card.role] }]}>
                        {ROLE_DISPLAY_NAMES[card.role]}
                      </Text>
                    </View>
                    <Text style={sheetStyles.rowAbility} numberOfLines={3}>{card.ability_text}</Text>
                  </View>
                  {isSel && <Ionicons name="checkmark-circle" size={22} color={colors.primary} />}
                </TouchableOpacity>
              );
            })
          )}
          {selected && (
            <TouchableOpacity style={sheetStyles.primaryBtn} onPress={() => onResolve(selected)}>
              <Text style={sheetStyles.primaryBtnText}>Become This Identity</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={sheetStyles.secondaryBtn} onPress={() => onResolve(null)}>
            <Text style={sheetStyles.secondaryBtnText}>Decline</Text>
          </TouchableOpacity>
        </>
      )}
      {!hasRevealed && (
        <TouchableOpacity style={sheetStyles.secondaryBtn} onPress={onDismiss}>
          <Text style={sheetStyles.secondaryBtnText}>Skip</Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

// ── Main Dev Testing Screen ──────────────────────────────────────

export default function DevTestAbilitiesScreen() {
  const [selectedAbility, setSelectedAbility] = useState<AbilityType>('wearerOfMasks');
  const [players, setPlayers] = useState<Player[]>(() => buildMockPlayers('wearerOfMasks'));
  const [showSheet, setShowSheet] = useState(false);
  const [stateLog, setStateLog] = useState<string[]>([]);

  const cardForAbility = useMemo(() => getCard(ABILITY_CARD_IDS[selectedAbility]), [selectedAbility]);

  const reset = useCallback((ability: AbilityType) => {
    setPlayers(buildMockPlayers(ability));
    setShowSheet(false);
    setStateLog([]);
  }, []);

  const logState = useCallback((ps: Player[]) => {
    const lines = ps.map((p) => {
      const card = p.identity_card_id ? getCard(p.identity_card_id) : undefined;
      const flags: string[] = [];
      if (p.is_face_down) flags.push('face-down');
      if (p.original_identity_card_id) flags.push('swapped');
      const flagStr = flags.length > 0 ? ` [${flags.join(', ')}]` : '';
      return `${p.display_name}: ${card?.name ?? '?'} (${p.role ? ROLE_DISPLAY_NAMES[p.role] : '?'})${flagStr}`;
    });
    setStateLog((prev) => [...lines, '---', ...prev]);
  }, []);

  const handleResolveMetamorph = (targetId: string) => {
    setPlayers((prev) => {
      const target = prev.find((p) => p.id === targetId);
      if (!target) return prev;
      const updated = prev.map((p) => {
        if (p.user_id !== 'dev_user') return p;
        return {
          ...p,
          original_identity_card_id: p.original_identity_card_id ?? p.identity_card_id,
          identity_card_id: target.identity_card_id,
          is_face_down: target.role !== 'leader',
        };
      });
      logState(updated);
      return updated;
    });
    setShowSheet(false);
  };

  const handleResolvePuppetMaster = (assignments: Record<string, string>) => {
    setPlayers((prev) => {
      const updated = prev.map((p) => {
        const newCardId = assignments[p.id];
        if (!newCardId || newCardId === p.identity_card_id) return p;
        const newCard = getCard(newCardId);
        return {
          ...p,
          original_identity_card_id: p.original_identity_card_id ?? p.identity_card_id,
          identity_card_id: newCardId,
          is_face_down: newCard ? newCard.role !== 'leader' : true,
        };
      });
      logState(updated);
      return updated;
    });
    setShowSheet(false);
  };

  const handleResolveWearerOfMasks = (cardId: string | null) => {
    if (cardId) {
      setPlayers((prev) => {
        const updated = prev.map((p) => {
          if (p.user_id !== 'dev_user') return p;
          return {
            ...p,
            original_identity_card_id: p.original_identity_card_id ?? p.identity_card_id,
            identity_card_id: cardId,
          };
        });
        logState(updated);
        return updated;
      });
    }
    setShowSheet(false);
  };

  const isDevToolsEnabled = process.env.EXPO_PUBLIC_ENVIRONMENT !== 'production';
  if (!isDevToolsEnabled) return null;

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.scroll}>
        {/* Header */}
        <View style={styles.headerSection}>
          <Ionicons name="hammer" size={32} color={colors.primary} />
          <Text style={styles.headerTitle}>Traitor Ability Tester</Text>
          <Text style={styles.headerSub}>Test ability UIs with mock game state</Text>
        </View>

        {/* Ability Picker */}
        <View style={styles.section}>
          <Text style={styles.sectionLabel}>Select Ability</Text>
          <View style={styles.pickerRow}>
            {(['wearerOfMasks', 'metamorph', 'puppetMaster'] as AbilityType[]).map((a) => (
              <TouchableOpacity
                key={a}
                style={[styles.pickerBtn, selectedAbility === a && styles.pickerBtnActive]}
                onPress={() => { setSelectedAbility(a); reset(a); }}
              >
                <Text style={[styles.pickerText, selectedAbility === a && styles.pickerTextActive]}>
                  {ABILITY_NAMES[a].replace('The ', '')}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {/* Card Ability */}
        <View style={styles.section}>
          <Text style={styles.sectionLabel}>Card Ability</Text>
          {cardForAbility && <Text style={styles.abilityText}>{cardForAbility.ability_text}</Text>}
        </View>

        {/* Game State */}
        <View style={styles.section}>
          <Text style={styles.sectionLabel}>Game State</Text>
          {players.map((p) => {
            const card = p.identity_card_id ? getCard(p.identity_card_id) : undefined;
            return (
              <View key={p.id} style={styles.stateRow}>
                <View style={[styles.stateDot, { backgroundColor: p.role ? ROLE_COLORS[p.role] : colors.textSecondary }]} />
                <View style={{ flex: 1 }}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
                    <Text style={styles.stateName}>{p.display_name}</Text>
                    {p.user_id === 'dev_user' && <Text style={styles.youBadge}>YOU</Text>}
                    {p.is_eliminated && <Text style={styles.elimBadge}>ELIMINATED</Text>}
                    {p.is_face_down && <Text style={styles.faceBadge}>FACE DOWN</Text>}
                  </View>
                  <Text style={styles.stateCard}>
                    {p.role ? ROLE_DISPLAY_NAMES[p.role] : '?'} — {card?.name ?? '?'}
                  </Text>
                </View>
                <Text style={styles.stateLife}>{p.life_total} HP</Text>
              </View>
            );
          })}
        </View>

        {/* Actions */}
        <TouchableOpacity style={styles.primaryBtn} onPress={() => setShowSheet(true)}>
          <Ionicons name="flash" size={18} color="#0d0b1a" />
          <Text style={styles.primaryBtnText}>Trigger {ABILITY_NAMES[selectedAbility]}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.secondaryBtn} onPress={() => reset(selectedAbility)}>
          <Ionicons name="refresh" size={16} color={colors.primary} />
          <Text style={styles.secondaryBtnText}>Reset Scenario</Text>
        </TouchableOpacity>

        {/* Log */}
        {stateLog.length > 0 && (
          <View style={styles.section}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <Text style={styles.sectionLabel}>State Changes</Text>
              <TouchableOpacity onPress={() => setStateLog([])}>
                <Text style={{ color: colors.textSecondary, fontSize: 11 }}>Clear</Text>
              </TouchableOpacity>
            </View>
            {stateLog.map((line, i) => (
              <Text key={i} style={styles.logLine}>{line}</Text>
            ))}
          </View>
        )}
      </ScrollView>

      {/* Sheet overlay */}
      {showSheet && (
        <View style={styles.overlay}>
          <ScrollView style={styles.sheetScroll} contentContainerStyle={styles.sheetScrollContent}>
            {selectedAbility === 'metamorph' && (
              <MetamorphSheet
                players={players}
                onResolve={handleResolveMetamorph}
                onDismiss={() => setShowSheet(false)}
              />
            )}
            {selectedAbility === 'puppetMaster' && (
              <PuppetMasterSheet
                players={players}
                onResolve={handleResolvePuppetMaster}
                onDismiss={() => setShowSheet(false)}
              />
            )}
            {selectedAbility === 'wearerOfMasks' && (
              <WearerOfMasksSheet
                players={players}
                onResolve={handleResolveWearerOfMasks}
                onDismiss={() => setShowSheet(false)}
              />
            )}
          </ScrollView>
        </View>
      )}
    </View>
  );
}

// ── Styles ───────────────────────────────────────────────────────

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.lg, gap: spacing.lg, maxWidth: 500, alignSelf: 'center', width: '100%' },
  headerSection: { alignItems: 'center', gap: 6, paddingVertical: spacing.md },
  headerTitle: { color: colors.text, fontSize: 22, fontWeight: 'bold', fontFamily: fonts.serif },
  headerSub: { color: colors.textSecondary, fontSize: 12 },
  section: {
    backgroundColor: colors.surface, borderRadius: 12, padding: spacing.md,
    borderWidth: 1, borderColor: colors.divider, gap: 8,
  },
  sectionLabel: { color: colors.primary, fontSize: 11, fontWeight: 'bold', textTransform: 'uppercase' },
  abilityText: { color: colors.textSecondary, fontSize: 12, lineHeight: 18 },
  pickerRow: { flexDirection: 'row', gap: 6 },
  pickerBtn: {
    flex: 1, paddingVertical: 8, borderRadius: 6, alignItems: 'center',
    backgroundColor: colors.surfaceLight, borderWidth: 1, borderColor: colors.divider,
  },
  pickerBtnActive: { backgroundColor: ROLE_COLORS.traitor + '25', borderColor: ROLE_COLORS.traitor },
  pickerText: { color: colors.textSecondary, fontSize: 11, fontWeight: '600' },
  pickerTextActive: { color: ROLE_COLORS.traitor },
  stateRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 4 },
  stateDot: { width: 8, height: 8, borderRadius: 4 },
  stateName: { color: colors.text, fontSize: 13, fontWeight: '600' },
  stateCard: { color: colors.textSecondary, fontSize: 11 },
  stateLife: { color: colors.textSecondary, fontSize: 12 },
  youBadge: { color: colors.primary, fontSize: 9, fontWeight: '700', backgroundColor: colors.primary + '25', paddingHorizontal: 4, paddingVertical: 1, borderRadius: 4, overflow: 'hidden' },
  elimBadge: { color: colors.error, fontSize: 9, fontWeight: '700', backgroundColor: colors.error + '20', paddingHorizontal: 4, paddingVertical: 1, borderRadius: 4, overflow: 'hidden' },
  faceBadge: { color: ROLE_COLORS.traitor, fontSize: 9, fontWeight: '700', backgroundColor: ROLE_COLORS.traitor + '20', paddingHorizontal: 4, paddingVertical: 1, borderRadius: 4, overflow: 'hidden' },
  primaryBtn: {
    backgroundColor: colors.primary, borderRadius: 8, paddingVertical: 14, alignItems: 'center',
    flexDirection: 'row', justifyContent: 'center', gap: 8,
  },
  primaryBtnText: { color: '#0d0b1a', fontSize: 15, fontWeight: '700' },
  secondaryBtn: {
    borderRadius: 8, paddingVertical: 12, alignItems: 'center', borderWidth: 1,
    borderColor: colors.primary, flexDirection: 'row', justifyContent: 'center', gap: 6,
  },
  secondaryBtnText: { color: colors.primary, fontSize: 14, fontWeight: '600' },
  logLine: { color: colors.textSecondary, fontSize: 11, fontFamily: 'monospace' },
  overlay: {
    ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'flex-end',
  },
  sheetScroll: {
    maxHeight: '85%', backgroundColor: colors.background,
    borderTopLeftRadius: 16, borderTopRightRadius: 16,
  },
  sheetScrollContent: { padding: spacing.lg },
});

const sheetStyles = StyleSheet.create({
  container: { gap: spacing.md, alignItems: 'center' },
  title: { color: colors.text, fontSize: 20, fontWeight: 'bold', fontFamily: fonts.serif },
  reminder: { color: colors.textSecondary, fontSize: 12, textAlign: 'center', lineHeight: 18, paddingHorizontal: spacing.md },
  emptyBox: {
    alignItems: 'center', gap: 8, padding: spacing.xl,
    backgroundColor: colors.surface, borderRadius: 12, borderWidth: 1, borderColor: colors.divider, width: '100%',
  },
  emptyText: { color: colors.text, fontSize: 14, fontWeight: '500' },
  emptyHint: { color: colors.textSecondary, fontSize: 12, textAlign: 'center' },
  row: {
    width: '100%', padding: spacing.md, backgroundColor: colors.surface, borderRadius: 8,
    borderWidth: 1, borderColor: colors.divider, flexDirection: 'row', alignItems: 'center', gap: 8,
  },
  rowSelected: { backgroundColor: ROLE_COLORS.traitor + '20', borderColor: ROLE_COLORS.traitor },
  rowSwapped: { borderColor: ROLE_COLORS.traitor + '60' },
  rowName: { color: colors.text, fontSize: 14, fontWeight: '600' },
  rowRole: { fontSize: 12, fontWeight: '500' },
  rowAbility: { color: colors.textSecondary, fontSize: 11, marginTop: 2, lineHeight: 16 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  primaryBtn: { backgroundColor: colors.primary, borderRadius: 8, paddingVertical: 14, width: '100%', alignItems: 'center' },
  primaryBtnText: { color: '#0d0b1a', fontSize: 15, fontWeight: '700' },
  secondaryBtn: { borderRadius: 8, paddingVertical: 12, width: '100%', alignItems: 'center', borderWidth: 1, borderColor: colors.primary },
  secondaryBtnText: { color: colors.primary, fontSize: 14, fontWeight: '600' },
  xLabel: { color: colors.text, fontSize: 14, fontWeight: '500' },
  xRow: { flexDirection: 'row', alignItems: 'center', gap: 20 },
  xValue: { color: colors.primary, fontSize: 48, fontWeight: 'bold', fontFamily: fonts.serif, minWidth: 60, textAlign: 'center' },
  instructionBox: {
    flexDirection: 'row', alignItems: 'center', gap: 6, padding: spacing.sm,
    backgroundColor: colors.surfaceLight, borderRadius: 8, width: '100%', justifyContent: 'center',
  },
  instructionText: { color: colors.text, fontSize: 12 },
  swapBadge: { backgroundColor: ROLE_COLORS.traitor, paddingHorizontal: 5, paddingVertical: 1, borderRadius: 4 },
  swapBadgeText: { color: '#0d0b1a', fontSize: 9, fontWeight: '700' },
});
