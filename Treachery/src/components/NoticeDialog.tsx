import React, { useEffect, useRef } from 'react';
import { Modal, View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { colors, fonts, spacing } from '@/constants/theme';

/**
 * In-app acknowledgement dialog — the one-button sibling of ConfirmDialog.
 *
 * Same reason it exists: RN-web compiles Alert.alert to a silent no-op, so
 * every `Alert.alert(title, message, [{ text: 'OK' }])` acknowledgement was
 * invisible on the web build. ConfirmDialog covers "are you sure?"; this
 * covers "here's what just happened".
 *
 * Pass autoDismissMs for transient notices (e.g. "Copied!") that shouldn't
 * need a tap to clear.
 */
export interface NoticeDialogProps {
  visible: boolean;
  title: string;
  message: string;
  /** Text shown on the dismiss button (e.g. "OK"). */
  dismissLabel?: string;
  /** Accessibility label for the dismiss button (e.g. "Dismiss copied notice"). */
  dismissAccessibilityLabel: string;
  /**
   * Auto-dismiss after this many ms; omit to require a tap.
   *
   * The timer starts when `visible` flips to true. Re-triggering a notice that
   * is already showing does not restart it — pass a changing `key` from the
   * caller to remount and reset the countdown.
   */
  autoDismissMs?: number;
  onDismiss: () => void;
}

export function NoticeDialog({
  visible,
  title,
  message,
  dismissLabel = 'OK',
  dismissAccessibilityLabel,
  autoDismissMs,
  onDismiss,
}: NoticeDialogProps) {
  // Held in a ref so a re-rendering parent (inline arrow onDismiss) can't
  // restart the auto-dismiss timer on every snapshot update.
  const dismissRef = useRef(onDismiss);
  useEffect(() => {
    dismissRef.current = onDismiss;
  }, [onDismiss]);

  useEffect(() => {
    if (!visible || autoDismissMs === undefined) return;
    const timer = setTimeout(() => dismissRef.current(), autoDismissMs);
    return () => clearTimeout(timer);
  }, [visible, autoDismissMs]);

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onDismiss}>
      <View style={styles.backdrop}>
        {/* Backdrop tap dismisses — same affordance as dismissing a native sheet */}
        <TouchableOpacity
          style={StyleSheet.absoluteFill}
          onPress={onDismiss}
          accessibilityLabel="Dismiss notice"
        />
        <View style={styles.card}>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.message}>{message}</Text>
          <View style={styles.buttonRow}>
            <TouchableOpacity
              style={styles.dismissButton}
              onPress={onDismiss}
              accessibilityLabel={dismissAccessibilityLabel}
              accessibilityRole="button"
            >
              <Text style={styles.dismissText}>{dismissLabel}</Text>
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
    marginTop: 6,
  },
  dismissButton: {
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    backgroundColor: colors.primary,
  },
  dismissText: {
    color: '#0d0b1a',
    fontSize: 15,
    fontWeight: '700',
  },
});
