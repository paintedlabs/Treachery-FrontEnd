import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  Modal,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PlaneCard } from '@/models/types';
import { colors, spacing, fonts } from '@/constants/theme';

interface InterplanarTunnelPickerProps {
  options: PlaneCard[];
  visible: boolean;
  onSelect: (planeId: string) => void;
  isSelecting: boolean;
}

export function InterplanarTunnelPicker({
  options,
  visible,
  onSelect,
  isSelecting,
}: InterplanarTunnelPickerProps) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      statusBarTranslucent
    >
      <View style={styles.overlay}>
        <View style={styles.card}>
          <View style={styles.header}>
            <Ionicons name="globe-outline" size={24} color={colors.primary} />
            <Text style={styles.title}>Interplanar Tunnel</Text>
          </View>
          <Text style={styles.subtitle}>Choose your next destination</Text>

          <View style={styles.divider} />

          {options.map((plane) => (
            <TouchableOpacity
              key={plane.id}
              style={styles.optionRow}
              onPress={() => onSelect(plane.id)}
              disabled={isSelecting}
              activeOpacity={0.7}
              accessibilityLabel={`Select ${plane.name}`}
              accessibilityRole="button"
            >
              <View style={styles.optionIcon}>
                <Ionicons name="planet" size={16} color={colors.primary} />
              </View>
              <View style={styles.optionText}>
                <Text style={styles.optionName} numberOfLines={1}>
                  {plane.name}
                </Text>
                <Text style={styles.optionType} numberOfLines={1}>
                  {plane.type_line}
                </Text>
              </View>
              {isSelecting ? (
                <ActivityIndicator size="small" color={colors.primary} />
              ) : (
                <Ionicons name="chevron-forward" size={14} color={colors.textTertiary} />
              )}
            </TouchableOpacity>
          ))}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    width: '100%',
    maxWidth: 400,
    padding: spacing.lg,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 4,
  },
  title: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    fontFamily: fonts.serif,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: 13,
    fontStyle: 'italic',
    marginBottom: spacing.sm,
  },
  divider: {
    height: 1,
    backgroundColor: colors.divider,
    marginBottom: spacing.sm,
  },
  optionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 12,
    paddingHorizontal: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  optionIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  optionText: {
    flex: 1,
    gap: 2,
  },
  optionName: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
  },
  optionType: {
    color: colors.primary,
    fontSize: 11,
    fontWeight: '500',
    letterSpacing: 0.5,
  },
});
