import React, { useState, useRef, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  Pressable,
  PressableStateCallbackType,
  ScrollView,
  StyleSheet,
  Animated,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Player } from '@/models/types';
import { ROLE_COLORS, ROLE_DISPLAY_NAMES } from '@/constants/roles';
import { colors, fonts, PLAYER_COLORS } from '@/constants/theme';

type WebPressableState = PressableStateCallbackType & { hovered?: boolean };

export type PlayerTileSize = 'normal' | 'tv';

/**
 * Outer size of a seat tile. Fixed on purpose: tiles sit in a ring, so the
 * container needs to know the box before it can place anything. Exported so the
 * seat layout can do its maths against the real numbers.
 */
export const TILE_WIDTH = 200;
export const TILE_HEIGHT = 150;

/** Outer size of the 'tv' spectator variant. */
export const TV_TILE_WIDTH = 300;
export const TV_TILE_HEIGHT = 220;

/** Height the colour-picker strip animates open to, inside the tile. */
const PICKER_HEIGHT = 44;

/** Box for a given variant, for containers that render both. */
export function tileDimensions(size: PlayerTileSize = 'normal'): {
  width: number;
  height: number;
} {
  return size === 'tv'
    ? { width: TV_TILE_WIDTH, height: TV_TILE_HEIGHT }
    : { width: TILE_WIDTH, height: TILE_HEIGHT };
}

export interface PlayerTileProps {
  player: Player;
  isCurrentUser: boolean;
  /** Highlight ring + badge: it is this player's turn. */
  isActiveTurn: boolean;
  /** Whether the viewer may see this player's role. */
  canSeeRole: boolean;
  isUnveiledOrLeader: boolean;
  onAdjustLife: (amount: number) => void;
  onViewCard?: () => void;
  /** Own tile only: inline rename (pencil affordance, same UX as PlayerRow's). */
  onRename?: (name: string) => void;
  onColorChange?: (color: string | null) => void;
  playerColor?: string | null;
  /** Visual state while this tile is being dragged (lifted/shadowed/semi-transparent). */
  isDragging?: boolean;
  /** Visual state when a dragged tile would drop here (highlighted outline). */
  isDropTarget?: boolean;
  /** 'tv' is a larger variant for a future spectator screen: bigger life number, no controls. */
  size?: 'normal' | 'tv';
  /** Spectator / eliminated viewer: life buttons stay visible but do nothing. */
  isDisabled?: boolean;
}

export function PlayerTile({
  player,
  isCurrentUser,
  isActiveTurn,
  canSeeRole,
  isUnveiledOrLeader: _isUnveiledOrLeader,
  onAdjustLife,
  onViewCard,
  onRename,
  onColorChange,
  playerColor,
  isDragging,
  isDropTarget,
  size = 'normal',
  isDisabled,
}: PlayerTileProps) {
  const isTv = size === 'tv';

  // The board already worked out who may see what (own card, the Leader,
  // anything unveiled face-up, the Puppet Master's peek). The tile trusts that
  // answer instead of re-deriving a weaker one from the player document.
  const visibleRole = canSeeRole ? player.role : null;
  const roleColor = visibleRole ? ROLE_COLORS[visibleRole] : colors.textSecondary;
  const effectiveColor = player.player_color || playerColor;
  const canInspectCard = canSeeRole && !isCurrentUser && !isTv && !!onViewCard;

  // The tv variant is a read-only spectator screen — no editing your own seat on it.
  const showOwnControls = isCurrentUser && !isTv;

  const [showColorPicker, setShowColorPicker] = useState(false);
  const [isEditingName, setIsEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState(player.display_name);
  const pickerHeight = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(pickerHeight, {
      toValue: showColorPicker ? PICKER_HEIGHT : 0,
      duration: 200,
      useNativeDriver: false,
    }).start();
  }, [showColorPicker, pickerHeight]);

  const submitRename = () => {
    setIsEditingName(false);
    const trimmed = nameDraft.trim();
    if (trimmed && trimmed !== player.display_name) {
      onRename?.(trimmed);
    } else {
      setNameDraft(player.display_name);
    }
  };

  const handleColorSelect = (hex: string) => {
    onColorChange?.(hex);
    setShowColorPicker(false);
  };

  const handleClearColor = () => {
    onColorChange?.(null);
    setShowColorPicker(false);
  };

  // Top trim, in ascending precedence — the last thing that applies wins.
  let trimColor: string = colors.border;
  if (isCurrentUser) trimColor = colors.primary;
  if (visibleRole) trimColor = roleColor;
  if (effectiveColor) trimColor = effectiveColor;
  if (player.is_eliminated) trimColor = colors.error;

  // Border carries three mutually exclusive states; drop target wins because it
  // is the only one that answers "what happens if I let go right now?".
  let borderColor: string = colors.border;
  if (isCurrentUser) borderColor = 'rgba(201, 168, 76, 0.45)';
  if (isActiveTurn) borderColor = colors.primary;
  if (isDropTarget) borderColor = colors.success;

  return (
    <View
      style={[
        styles.tile,
        isTv && styles.tileTv,
        isCurrentUser && styles.tileYou,
        player.is_eliminated && styles.tileEliminated,
        { borderColor },
        isDropTarget && styles.tileDropTarget,
        isDragging && styles.tileDragging,
      ]}
    >
      <View style={[styles.trim, { backgroundColor: trimColor }]} />

      {/* Turn marker: a gold ring AND a worded chip, so the state never rests on
          colour alone. */}
      {isActiveTurn && (
        <View style={styles.turnBadge}>
          <Ionicons name="caret-forward" size={9} color={colors.primary} />
          <Text style={styles.turnText}>Turn</Text>
        </View>
      )}

      <View style={[styles.head, isActiveTurn && styles.headWithTurnBadge]}>
        {showOwnControls && onColorChange && (
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

        {isEditingName ? (
          <TextInput
            style={[styles.name, styles.nameBold, styles.nameInput]}
            value={nameDraft}
            onChangeText={setNameDraft}
            onBlur={submitRename}
            onSubmitEditing={submitRename}
            autoFocus
            maxLength={40}
            returnKeyType="done"
            accessibilityLabel="Your name"
          />
        ) : (
          <Text
            numberOfLines={1}
            style={[
              styles.name,
              isTv && styles.nameTv,
              isCurrentUser && styles.nameBold,
              player.is_eliminated && styles.nameEliminated,
            ]}
          >
            {player.display_name}
          </Text>
        )}

        {showOwnControls && onRename && !isEditingName && (
          <TouchableOpacity
            onPress={() => {
              setNameDraft(player.display_name);
              setIsEditingName(true);
            }}
            accessibilityLabel="Edit your name"
            accessibilityRole="button"
            hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }}
          >
            <Ionicons name="pencil" size={13} color={colors.textSecondary} />
          </TouchableOpacity>
        )}

        {isCurrentUser && (
          <View style={styles.youBadge}>
            <Text style={styles.youText}>You</Text>
          </View>
        )}

        {player.is_eliminated && <Ionicons name="close-circle" size={13} color={colors.error} />}
      </View>

      {player.commander_name ? (
        <Text numberOfLines={1} style={[styles.commanderName, isTv && styles.commanderNameTv]}>
          {player.commander_name}
        </Text>
      ) : null}

      <View style={styles.lifeRow}>
        {!player.is_eliminated && !isTv && (
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
            <Ionicons name="remove-circle" size={30} color={colors.error} />
          </Pressable>
        )}

        <View style={[styles.lifeBox, isTv && styles.lifeBoxTv]}>
          <Text
            style={[
              styles.lifeText,
              isTv && styles.lifeTextTv,
              player.is_eliminated && styles.lifeTextDead,
            ]}
          >
            {player.life_total}
          </Text>
        </View>

        {!player.is_eliminated && !isTv && (
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
            <Ionicons name="add-circle" size={30} color={colors.success} />
          </Pressable>
        )}
      </View>

      {player.is_eliminated ? (
        <View style={styles.footerRow}>
          <Ionicons name="skull" size={11} color={colors.error} />
          <Text style={[styles.eliminatedText, isTv && styles.footerTextTv]}>Eliminated</Text>
          {visibleRole && (
            <Text
              style={[styles.eliminatedRole, isTv && styles.footerTextTv, { color: roleColor }]}
            >
              {ROLE_DISPLAY_NAMES[visibleRole]}
            </Text>
          )}
        </View>
      ) : visibleRole ? (
        <Pressable
          onPress={canInspectCard ? onViewCard : undefined}
          style={({ hovered }: WebPressableState) => [
            styles.footerRow,
            styles.roleRow,
            hovered && canInspectCard && styles.roleRowHovered,
          ]}
          disabled={!canInspectCard}
          accessibilityLabel={`${ROLE_DISPLAY_NAMES[visibleRole]} role${canInspectCard ? ', view card' : ''}`}
          accessibilityRole="button"
        >
          <View
            style={[styles.roleDot, isTv && styles.roleDotTv, { backgroundColor: roleColor }]}
          />
          <Text style={[styles.roleText, isTv && styles.footerTextTv, { color: roleColor }]}>
            {ROLE_DISPLAY_NAMES[visibleRole]}
          </Text>
          {player.is_unveiled && visibleRole !== 'leader' && !isCurrentUser && (
            <Text style={styles.unveiledText}>(Unveiled)</Text>
          )}
          {canInspectCard && (
            <Ionicons name="information-circle-outline" size={12} color={roleColor} />
          )}
        </Pressable>
      ) : (
        <View style={styles.footerRow}>
          <Text style={[styles.hiddenText, isTv && styles.footerTextTv]}>Role Hidden</Text>
        </View>
      )}

      {/* Colour picker — overlaid on the tile rather than pushed below it, because
          the seat ring is laid out against a fixed TILE_HEIGHT. */}
      {showOwnControls && onColorChange && (
        <Animated.View style={[styles.colorPicker, { height: pickerHeight }]}>
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
                <Ionicons name="close" size={13} color={colors.textSecondary} />
              </View>
            </TouchableOpacity>
          </ScrollView>
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  tile: {
    width: TILE_WIDTH,
    height: TILE_HEIGHT,
    backgroundColor: colors.surface,
    // Always 2px so the active-turn ring is a colour change, not a size change —
    // a tile that grew on its own turn would shove its neighbours around.
    borderWidth: 2,
    borderColor: colors.border,
    borderRadius: 12,
    paddingTop: 14,
    paddingHorizontal: 12,
    paddingBottom: 10,
    gap: 4,
    overflow: 'hidden',
  },
  tileTv: {
    width: TV_TILE_WIDTH,
    height: TV_TILE_HEIGHT,
    borderRadius: 16,
    paddingTop: 18,
    paddingHorizontal: 18,
    paddingBottom: 14,
  },
  tileYou: {
    backgroundColor: colors.surfaceLight,
  },
  tileEliminated: {
    opacity: 0.55,
  },
  tileDropTarget: {
    borderStyle: 'dashed',
    backgroundColor: 'rgba(60, 168, 92, 0.12)',
  },
  tileDragging: {
    opacity: 0.85,
    transform: [{ scale: 1.04 }],
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.45,
    shadowRadius: 18,
  },
  trim: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 3,
  },
  turnBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    backgroundColor: 'rgba(201, 168, 76, 0.2)',
    borderWidth: 1,
    borderColor: 'rgba(201, 168, 76, 0.45)',
    borderRadius: 8,
    paddingHorizontal: 5,
    paddingVertical: 1,
  },
  turnText: {
    color: colors.primary,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  head: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  headWithTurnBadge: {
    // Keep the name clear of the absolutely-placed Turn chip.
    paddingRight: 44,
  },
  colorCircle: {
    width: 14,
    height: 14,
    borderRadius: 7,
  },
  colorCircleEmpty: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderStyle: 'dashed',
  },
  name: {
    color: colors.text,
    fontSize: 15,
    flexShrink: 1,
  },
  nameTv: {
    fontSize: 22,
  },
  nameBold: {
    fontWeight: 'bold',
  },
  nameEliminated: {
    textDecorationLine: 'line-through',
    color: colors.textSecondary,
  },
  nameInput: {
    // Match the Text metrics so the tile doesn't jump while editing.
    padding: 0,
    margin: 0,
    minWidth: 110,
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
    fontSize: 11,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  commanderNameTv: {
    fontSize: 14,
  },
  lifeRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  lifeBox: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingVertical: 2,
    paddingHorizontal: 8,
    minWidth: 56,
    alignItems: 'center',
  },
  lifeBoxTv: {
    minWidth: 130,
    paddingHorizontal: 16,
    borderRadius: 10,
  },
  lifeText: {
    color: colors.text,
    fontSize: 30,
    // Explicit line height keeps the fixed tile height predictable across platforms.
    lineHeight: 36,
    fontWeight: '700',
    fontFamily: fonts.serif,
    textAlign: 'center',
  },
  lifeTextTv: {
    fontSize: 68,
    lineHeight: 78,
  },
  lifeTextDead: {
    color: colors.textTertiary,
    textDecorationLine: 'line-through',
  },
  lifeButton: {
    borderRadius: 18,
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
  footerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    minHeight: 16,
  },
  footerTextTv: {
    fontSize: 16,
  },
  roleRow: {
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
  roleDotTv: {
    width: 11,
    height: 11,
    borderRadius: 6,
  },
  roleText: {
    fontSize: 11,
    fontWeight: '600',
  },
  unveiledText: {
    fontSize: 9,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  hiddenText: {
    fontSize: 11,
    color: colors.textTertiary,
    fontStyle: 'italic',
  },
  eliminatedText: {
    color: colors.error,
    fontSize: 11,
    fontStyle: 'italic',
  },
  eliminatedRole: {
    fontSize: 11,
    fontWeight: '600',
  },
  colorPicker: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    overflow: 'hidden',
    backgroundColor: colors.background,
    borderTopWidth: 1,
    borderTopColor: colors.divider,
  },
  colorPickerContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  colorOption: {
    width: 22,
    height: 22,
    borderRadius: 11,
  },
  colorOptionSelected: {
    borderWidth: 2.5,
    borderColor: colors.text,
  },
  colorClear: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
