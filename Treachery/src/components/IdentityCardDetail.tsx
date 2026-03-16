import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Modal,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player, IdentityCard, Rarity } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES, ROLE_WIN_CONDITIONS } from '@/constants/roles';
import { RARITY_DISPLAY_NAMES, RARITY_COLORS } from '@/constants/roles';
import { colors, fonts } from '@/constants/theme';

interface IdentityCardDetailProps {
  card: IdentityCard;
  player: Player;
  visible: boolean;
  onClose: () => void;
}

export function IdentityCardDetail({ card, player, visible, onClose }: IdentityCardDetailProps) {
  const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;
  const rarityColor = RARITY_COLORS[card.rarity] ?? colors.textSecondary;

  return (
    <Modal
      visible={visible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={onClose}
    >
      <View style={styles.modalContainer}>
        {/* Header bar */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Identity Card</Text>
          <TouchableOpacity
            onPress={onClose}
            accessibilityLabel="Close identity card"
            accessibilityRole="button"
          >
            <Text style={styles.doneButton}>Done</Text>
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
          {/* Card frame */}
          <View style={[styles.cardFrame, { borderColor: roleColor }]}>
            {/* Top gold trim */}
            <View style={[styles.topTrim, { backgroundColor: roleColor }]} />

            {/* Title bar */}
            <View style={[styles.titleBar, { backgroundColor: roleColor + '15' }]}>
              <Text style={styles.cardName}>{card.name}</Text>
              <Text style={styles.cardNumber}>#{card.card_number}</Text>
            </View>

            <View style={styles.divider} />

            {/* Role & Rarity */}
            <View style={styles.roleRarityRow}>
              <View style={styles.roleRow}>
                <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
                <Text style={[styles.roleText, { color: roleColor }]}>
                  {player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'}
                </Text>
              </View>
              <Text style={[styles.rarityText, { color: rarityColor }]}>
                {RARITY_DISPLAY_NAMES[card.rarity]}
              </Text>
            </View>

            {/* Ornate divider */}
            <View style={styles.ornateDividerRow}>
              <View style={styles.ornateLine} />
              <Text style={[styles.ornateDiamond, { color: roleColor }]}>&#9670;</Text>
              <View style={styles.ornateLine} />
            </View>

            {/* Ability */}
            <View style={styles.section}>
              <Text style={styles.sectionLabel}>Ability</Text>
              <Text style={styles.abilityText}>{card.ability_text}</Text>
            </View>

            <View style={styles.divider} />

            {/* Unveil cost */}
            <View style={styles.unveilRow}>
              <Ionicons name="eye" size={18} color={roleColor} />
              <View style={styles.unveilInfo}>
                <Text style={styles.sectionLabel}>Unveil Cost</Text>
                <Text style={styles.unveilCost}>{card.unveil_cost}</Text>
              </View>
              {player.is_unveiled && (
                <View style={[styles.unveiledBadge, { backgroundColor: roleColor }]}>
                  <Text style={styles.unveiledText}>UNVEILED</Text>
                </View>
              )}
            </View>

            {/* Undercover condition */}
            {card.has_undercover && card.undercover_condition && (
              <>
                <View style={styles.divider} />
                <View style={styles.infoRow}>
                  <Ionicons name="glasses" size={18} color="#9c4cc9" />
                  <View style={styles.infoContent}>
                    <Text style={styles.sectionLabel}>Undercover</Text>
                    <Text style={styles.infoText}>{card.undercover_condition}</Text>
                  </View>
                </View>
              </>
            )}

            {/* Timing restriction */}
            {card.timing_restriction && (
              <>
                <View style={styles.divider} />
                <View style={styles.infoRow}>
                  <Ionicons name="time" size={18} color={colors.warning} />
                  <View style={styles.infoContent}>
                    <Text style={styles.sectionLabel}>Timing</Text>
                    <Text style={styles.infoText}>{card.timing_restriction}</Text>
                  </View>
                </View>
              </>
            )}

            {/* Modifiers */}
            {(card.life_modifier !== null || card.hand_size_modifier !== null) && (
              <>
                <View style={styles.divider} />
                <View style={styles.modifiersRow}>
                  {card.life_modifier !== null && (
                    <View style={styles.modifierBox}>
                      <Ionicons name="heart" size={14} color={colors.error} />
                      <Text style={styles.modifierValue}>
                        {card.life_modifier >= 0 ? '+' : ''}
                        {card.life_modifier}
                      </Text>
                      <Text style={styles.modifierLabel}>Life</Text>
                    </View>
                  )}
                  {card.hand_size_modifier !== null && (
                    <View style={styles.modifierBox}>
                      <Ionicons name="hand-left" size={14} color={colors.primary} />
                      <Text style={styles.modifierValue}>
                        {card.hand_size_modifier >= 0 ? '+' : ''}
                        {card.hand_size_modifier}
                      </Text>
                      <Text style={styles.modifierLabel}>Hand Size</Text>
                    </View>
                  )}
                </View>
              </>
            )}

            {/* Flavor text */}
            {card.flavor_text && (
              <>
                <View style={styles.divider} />
                <View style={styles.section}>
                  <Text style={styles.flavorText}>{card.flavor_text}</Text>
                </View>
              </>
            )}
          </View>

          {/* Win condition */}
          {player.role && (
            <View style={styles.winCondition}>
              {/* Ornate divider */}
              <View style={styles.ornateDividerRow}>
                <View style={styles.ornateLine} />
                <Text style={styles.ornateDiamondGold}>&#9670;</Text>
                <View style={styles.ornateLine} />
              </View>
              <Text style={styles.winConditionLabel}>Win Condition</Text>
              <Text style={styles.winConditionText}>
                {ROLE_WIN_CONDITIONS[player.role]}
              </Text>
            </View>
          )}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  modalContainer: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
    backgroundColor: colors.surface,
  },
  headerTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  doneButton: {
    color: colors.primary,
    fontSize: 17,
    fontWeight: '600',
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
  },
  cardFrame: {
    borderWidth: 2,
    borderRadius: 12,
    backgroundColor: colors.surface,
    overflow: 'hidden',
  },
  topTrim: {
    height: 4,
  },
  titleBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  cardName: {
    color: colors.text,
    fontSize: 18,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  cardNumber: {
    color: colors.textSecondary,
    fontSize: 12,
  },
  divider: {
    height: 1,
    backgroundColor: colors.divider,
  },
  roleRarityRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  roleDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  roleText: {
    fontSize: 14,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  rarityText: {
    fontSize: 12,
    fontWeight: '500',
    fontStyle: 'italic',
  },
  ornateDividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    gap: 8,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    fontSize: 8,
  },
  ornateDiamondGold: {
    color: colors.primary,
    fontSize: 8,
  },
  section: {
    padding: 16,
  },
  sectionLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: 'bold',
    marginBottom: 4,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  abilityText: {
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
  unveilRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 16,
  },
  unveilInfo: {
    flex: 1,
  },
  unveilCost: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '500',
  },
  unveiledBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 10,
  },
  unveiledText: {
    color: '#0d0b1a',
    fontSize: 11,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    padding: 16,
  },
  infoContent: {
    flex: 1,
  },
  infoText: {
    color: colors.text,
    fontSize: 14,
  },
  modifiersRow: {
    flexDirection: 'row',
    gap: 24,
    padding: 16,
  },
  modifierBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 4,
    paddingHorizontal: 8,
  },
  modifierValue: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  modifierLabel: {
    color: colors.textSecondary,
    fontSize: 12,
  },
  flavorText: {
    color: colors.textTertiary,
    fontSize: 13,
    fontStyle: 'italic',
    fontFamily: fonts.serif,
  },
  winCondition: {
    alignItems: 'center',
    paddingVertical: 20,
    gap: 8,
  },
  winConditionLabel: {
    color: colors.primary,
    fontSize: 11,
    fontWeight: 'bold',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  winConditionText: {
    color: colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
    fontFamily: fonts.serif,
  },
});
