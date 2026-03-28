import React, { useState, useRef, useEffect } from 'react';
import { View, Text, TouchableOpacity, Pressable, PressableStateCallbackType, ScrollView, StyleSheet, Animated } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, fonts, PLAYER_COLORS } from '@/constants/theme';

type WebPressableState = PressableStateCallbackType & { hovered?: boolean };

interface PlayerRowProps {
  player: Player;
  isCurrentUser: boolean;
  canSeeRole: boolean;
  isUnveiledOrLeader: boolean;
  onAdjustLife: (amount: number) => void;
  onViewCard?: () => void;
  isDisabled?: boolean;
  onColorChange?: (color: string | null) => void;
  playerColor?: string | null;
}

export function PlayerRow({
  player,
  isCurrentUser,
  canSeeRole: _canSeeRole,
  isUnveiledOrLeader,
  onAdjustLife,
  onViewCard,
  isDisabled,
  onColorChange,
  playerColor,
}: PlayerRowProps) {
  const roleColor = player.role ? ROLE_COLORS[player.role] : colors.textSecondary;
  const effectiveColor = player.player_color || playerColor;
  const isPublicRole = player.role && (player.is_unveiled || player.role === 'leader');
  const accentColor = effectiveColor || (isPublicRole ? roleColor : null);

  const [showColorPicker, setShowColorPicker] = useState(false);
  const pickerHeight = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(pickerHeight, {
      toValue: showColorPicker ? 48 : 0,
      duration: 200,
      useNativeDriver: false,
    }).start();
  }, [showColorPicker, pickerHeight]);

  const handleColorSelect = (hex: string) => {
    onColorChange?.(hex);
    setShowColorPicker(false);
  };

  const handleClearColor = () => {
    onColorChange?.(null);
    setShowColorPicker(false);
  };

  return (
    <View>
      <View style={[styles.container, isCurrentUser && styles.containerHighlight]}>
        {/* Left accent bar — player color preferred over role color */}
        {accentColor && <View style={[styles.accentBar, { backgroundColor: accentColor }]} />}

        <View style={styles.info}>
          <View style={styles.nameRow}>
            {/* Color indicator circle for current user */}
            {isCurrentUser && onColorChange && (
              <TouchableOpacity
                onPress={() => setShowColorPicker(!showColorPicker)}
                accessibilityLabel="Choose player color"
                accessibilityRole="button"
                hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }}
              >
                <View
                  style={[
                    styles.colorCircle,
                    effectiveColor ? { backgroundColor: effectiveColor } : styles.colorCircleEmpty,
                  ]}
                />
              </TouchableOpacity>
            )}
            <Text
              style={[
                styles.name,
                isCurrentUser && styles.nameBold,
                player.is_eliminated && styles.nameEliminated,
              ]}
            >
              {player.display_name}
            </Text>
            {isCurrentUser && (
              <View style={styles.youBadge}>
                <Text style={styles.youText}>You</Text>
              </View>
            )}
            {player.is_eliminated && (
              <Ionicons name="close-circle" size={14} color={colors.error} />
            )}
          </View>

          {/* Commander name */}
          {player.commander_name ? (
            <Text style={styles.commanderName}>{player.commander_name}</Text>
          ) : null}

          {isPublicRole ? (
            <Pressable
              onPress={isUnveiledOrLeader && !isCurrentUser ? onViewCard : undefined}
              style={({ hovered }: WebPressableState) => [
                styles.roleRow,
                hovered && isUnveiledOrLeader && !isCurrentUser && styles.roleRowHovered,
              ]}
              disabled={!isUnveiledOrLeader || isCurrentUser}
              accessibilityLabel={`${player.role ? ROLE_DISPLAY_NAMES[player.role] : 'Unknown'} role${isUnveiledOrLeader && !isCurrentUser ? ', view card' : ''}`}
              accessibilityRole="button"
            >
              <View style={[styles.roleDot, { backgroundColor: roleColor }]} />
              <Text style={[styles.roleText, { color: roleColor }]}>
                {ROLE_DISPLAY_NAMES[player.role!]}
              </Text>
              {player.is_unveiled && player.role !== 'leader' && !isCurrentUser && (
                <Text style={styles.unveiledText}>(Unveiled)</Text>
              )}
              {isUnveiledOrLeader && !isCurrentUser && (
                <Ionicons name="information-circle-outline" size={12} color={roleColor} />
              )}
            </Pressable>
          ) : (
            <Text style={styles.hiddenText}>Role Hidden</Text>
          )}
        </View>

        {!player.is_eliminated ? (
          <View style={[styles.lifeControls, isDisabled && { opacity: 0.5 }]}>
            <Pressable
              onPress={() => onAdjustLife(-1)}
              disabled={isDisabled}
              style={({ hovered, pressed }: WebPressableState) => [
                styles.lifeButton,
                hovered && styles.lifeButtonDecrHovered,
                pressed && styles.lifeButtonPressed,
              ]}
              accessibilityLabel={`Decrease ${player.display_name} life`}
              accessibilityRole="button"
            >
              <Ionicons name="remove-circle" size={34} color={colors.error} />
            </Pressable>
            <View style={styles.lifeBox}>
              <Text style={styles.lifeText}>{player.life_total}</Text>
            </View>
            <Pressable
              onPress={() => onAdjustLife(1)}
              disabled={isDisabled}
              style={({ hovered, pressed }: WebPressableState) => [
                styles.lifeButton,
                hovered && styles.lifeButtonIncrHovered,
                pressed && styles.lifeButtonPressed,
              ]}
              accessibilityLabel={`Increase ${player.display_name} life`}
              accessibilityRole="button"
            >
              <Ionicons name="add-circle" size={34} color={colors.success} />
            </Pressable>
          </View>
        ) : (
          <Text style={styles.eliminatedText}>Eliminated</Text>
        )}
      </View>

      {/* Color picker strip — animated below the row */}
      {isCurrentUser && onColorChange && (
        <Animated.View style={[styles.colorPickerContainer, { height: pickerHeight }]}>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.colorPickerContent}
          >
            {PLAYER_COLORS.map((c) => (
              <TouchableOpacity
                key={c.hex}
                onPress={() => handleColorSelect(c.hex)}
                accessibilityLabel={`Select ${c.name} color`}
                accessibilityRole="button"
              >
                <View
                  style={[
                    styles.colorOption,
                    { backgroundColor: c.hex },
                    effectiveColor === c.hex && styles.colorOptionSelected,
                  ]}
                />
              </TouchableOpacity>
            ))}
            <TouchableOpacity
              onPress={handleClearColor}
              accessibilityLabel="Clear color"
              accessibilityRole="button"
            >
              <View style={styles.colorClear}>
                <Ionicons name="close" size={14} color={colors.textSecondary} />
              </View>
            </TouchableOpacity>
          </ScrollView>
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
    backgroundColor: colors.surface,
  },
  containerHighlight: {
    backgroundColor: colors.surfaceLight,
  },
  accentBar: {
    width: 3,
    alignSelf: 'stretch',
    borderRadius: 2,
    marginRight: 10,
  },
  info: {
    flex: 1,
    gap: 2,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  colorCircle: {
    width: 18,
    height: 18,
    borderRadius: 9,
  },
  colorCircleEmpty: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderStyle: 'dashed',
  },
  name: {
    color: colors.text,
    fontSize: 16,
  },
  nameBold: {
    fontWeight: 'bold',
  },
  nameEliminated: {
    textDecorationLine: 'line-through',
    color: colors.textSecondary,
  },
  youBadge: {
    backgroundColor: 'rgba(201, 168, 76, 0.2)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.3)',
    paddingHorizontal: 6,
    paddingVertical: 1,
    borderRadius: 10,
  },
  youText: {
    color: colors.primary,
    fontSize: 10,
    fontWeight: '600',
  },
  commanderName: {
    fontSize: 12,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  roleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderRadius: 4,
    paddingVertical: 1,
    paddingHorizontal: 2,
    marginHorizontal: -2,
  },
  roleRowHovered: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
  },
  roleDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  roleText: {
    fontSize: 12,
    fontWeight: '500',
  },
  unveiledText: {
    fontSize: 10,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  hiddenText: {
    fontSize: 12,
    color: colors.textTertiary,
    fontStyle: 'italic',
  },
  lifeControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  lifeBox: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 4,
    paddingHorizontal: 10,
    minWidth: 54,
    alignItems: 'center',
  },
  lifeText: {
    color: colors.text,
    fontSize: 28,
    fontWeight: '700',
    fontFamily: fonts.serif,
    textAlign: 'center',
  },
  lifeButton: {
    borderRadius: 20,
    padding: 2,
  },
  lifeButtonDecrHovered: {
    backgroundColor: 'rgba(196, 60, 60, 0.15)',
  },
  lifeButtonIncrHovered: {
    backgroundColor: 'rgba(60, 168, 92, 0.15)',
  },
  lifeButtonPressed: {
    opacity: 0.7,
  },
  eliminatedText: {
    color: colors.error,
    fontSize: 12,
    fontStyle: 'italic',
  },
  colorPickerContainer: {
    overflow: 'hidden',
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  colorPickerContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  colorOption: {
    width: 28,
    height: 28,
    borderRadius: 14,
  },
  colorOptionSelected: {
    borderWidth: 2.5,
    borderColor: colors.text,
  },
  colorClear: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
