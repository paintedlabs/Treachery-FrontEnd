import React from 'react';
import { Modal, View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { colors, fonts, spacing } from '@/constants/theme';

/**
 * In-app confirmation dialog, replacing window.confirm / Alert.alert forks.
 *
 * Why not the native ones: window.confirm renders outside the app (unthemed,
 * blocks the JS thread, and automation layers like Playwright auto-dismiss it
 * unless specially handled — in the playtest harness that made Unveil appear
 * to do nothing), and RN-web compiles Alert.alert to a silent no-op. One
 * component, one code path, every platform.
 *
 * The confirm button gets a DISTINCT accessibility label (e.g. "Confirm
 * unveil") so tests and screen readers can't collide with the button that
 * opened the dialog ("Unveil identity" vs "Unveil").
 */
export interface ConfirmDialogProps {
  visible: boolean;
  title: string;
  message: string;
  /** Text shown on the confirm button (e.g. "Unveil"). */
  confirmLabel: string;
  /** Accessibility label for the confirm button (e.g. "Confirm unveil"). */
  confirmAccessibilityLabel: string;
  /** Styles the confirm button red for irreversible/negative actions. */
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmDialog({
  visible,
  title,
  message,
  confirmLabel,
  confirmAccessibilityLabel,
  destructive = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel}>
      <View style={styles.backdrop}>
        {/* Backdrop tap cancels — same affordance as dismissing a native sheet */}
        <TouchableOpacity
          style={StyleSheet.absoluteFill}
          onPress={onCancel}
          accessibilityLabel="Dismiss dialog"
        />
        <View style={styles.card}>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.message}>{message}</Text>
          <View style={styles.buttonRow}>
            <TouchableOpacity
              style={styles.cancelButton}
              onPress={onCancel}
              accessibilityLabel="Cancel"
              accessibilityRole="button"
            >
              <Text style={styles.cancelText}>Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.confirmButton, destructive && styles.confirmButtonDestructive]}
              onPress={onConfirm}
              accessibilityLabel={confirmAccessibilityLabel}
              accessibilityRole="button"
            >
              <Text
                style={[styles.confirmText, destructive && styles.confirmTextDestructive]}
              >
                {confirmLabel}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  card: {
    width: '100%',
    maxWidth: 400,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderAccent,
    borderRadius: 12,
    padding: spacing.lg,
    gap: 10,
  },
  title: {
    color: colors.text,
    fontSize: 18,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
  },
  message: {
    color: colors.textSecondary,
    fontSize: 14,
    lineHeight: 20,
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
    marginTop: 6,
  },
  cancelButton: {
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
  cancelText: {
    color: colors.textSecondary,
    fontSize: 15,
    fontWeight: '600',
  },
  confirmButton: {
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    backgroundColor: colors.primary,
  },
  confirmButtonDestructive: {
    backgroundColor: colors.destructive,
  },
  confirmText: {
    color: '#0d0b1a',
    fontSize: 15,
    fontWeight: '700',
  },
  confirmTextDestructive: {
    color: colors.text,
  },
});
