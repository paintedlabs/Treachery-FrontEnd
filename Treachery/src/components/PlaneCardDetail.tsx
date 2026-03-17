import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Modal,
  Image,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { PlaneCard } from '@/models/types';
import { colors, fonts } from '@/constants/theme';

interface PlaneCardDetailProps {
  planeCard: PlaneCard;
  visible: boolean;
  onClose: () => void;
}

export function PlaneCardDetail({ planeCard, visible, onClose }: PlaneCardDetailProps) {
  const accentColor = planeCard.is_phenomenon ? colors.warning : colors.primary;
  const [rotated, setRotated] = useState(false);

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
          <Text style={styles.headerTitle}>
            {planeCard.is_phenomenon ? 'Phenomenon' : 'Plane'}
          </Text>
          <TouchableOpacity
            onPress={onClose}
            accessibilityLabel="Close plane card"
            accessibilityRole="button"
          >
            <Text style={styles.doneButton}>Done</Text>
          </TouchableOpacity>
        </View>

        <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
          {/* Card image */}
          {planeCard.image_uri && (
            <View style={styles.imageContainer}>
              <Image
                source={{ uri: planeCard.image_uri }}
                style={[
                  styles.cardImage,
                  rotated && styles.cardImageRotated,
                ]}
                resizeMode="contain"
              />
              <TouchableOpacity
                style={styles.rotateButton}
                onPress={() => setRotated((r) => !r)}
                accessibilityLabel={rotated ? 'Reset card rotation' : 'Rotate card 90 degrees'}
                accessibilityRole="button"
              >
                <Ionicons name="refresh" size={18} color={colors.textSecondary} />
              </TouchableOpacity>
            </View>
          )}

          {/* Card frame */}
          <View style={[styles.cardFrame, { borderColor: accentColor }]}>
            {/* Top trim */}
            <View style={[styles.topTrim, { backgroundColor: accentColor }]} />

            {/* Title bar */}
            <View style={[styles.titleBar, { backgroundColor: accentColor + '15' }]}>
              <View style={styles.titleRow}>
                <Ionicons
                  name={planeCard.is_phenomenon ? 'flash' : 'planet'}
                  size={18}
                  color={accentColor}
                />
                <Text style={styles.cardName}>{planeCard.name}</Text>
              </View>
            </View>

            <View style={styles.divider} />

            {/* Type line */}
            <View style={styles.typeLineRow}>
              <Text style={[styles.typeLineText, { color: accentColor }]}>
                {planeCard.type_line}
              </Text>
              {planeCard.is_phenomenon && (
                <View style={styles.phenomenonBadge}>
                  <Text style={styles.phenomenonBadgeText}>PHENOMENON</Text>
                </View>
              )}
            </View>

            {/* Ornate divider */}
            <View style={styles.ornateDividerRow}>
              <View style={styles.ornateLine} />
              <Text style={[styles.ornateDiamond, { color: accentColor }]}>&#9670;</Text>
              <View style={styles.ornateLine} />
            </View>

            {/* Oracle text */}
            <View style={styles.section}>
              <Text style={styles.sectionLabel}>Oracle Text</Text>
              <Text style={styles.oracleText}>{planeCard.oracle_text}</Text>
            </View>
          </View>
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
    gap: 16,
  },
  imageContainer: {
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  cardImage: {
    width: '100%',
    aspectRatio: 626 / 457, // Standard MTG plane card ratio (landscape)
  },
  cardImageRotated: {
    transform: [{ rotate: '90deg' }],
    // After rotation the image's width becomes the height and vice versa,
    // so scale it down to fit within the container
    width: '73%',
    alignSelf: 'center' as const,
    aspectRatio: 457 / 626,
  },
  rotateButton: {
    position: 'absolute' as const,
    bottom: 8,
    right: 8,
    backgroundColor: 'rgba(13, 11, 26, 0.7)',
    borderRadius: 16,
    width: 32,
    height: 32,
    alignItems: 'center' as const,
    justifyContent: 'center' as const,
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
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  cardName: {
    color: colors.text,
    fontSize: 18,
    fontWeight: 'bold',
    fontFamily: fonts.serif,
    fontStyle: 'italic',
    flex: 1,
  },
  divider: {
    height: 1,
    backgroundColor: colors.divider,
  },
  typeLineRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  typeLineText: {
    fontSize: 13,
    fontWeight: '500',
    letterSpacing: 0.5,
  },
  phenomenonBadge: {
    backgroundColor: 'rgba(212, 148, 60, 0.15)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
  },
  phenomenonBadgeText: {
    color: colors.warning,
    fontSize: 10,
    fontWeight: 'bold',
    letterSpacing: 1,
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
  oracleText: {
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
  },
});
