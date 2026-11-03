import React from 'react';
import { TouchableOpacity, Image, StyleSheet } from 'react-native';
import { colors } from '@/constants/theme';

interface SidebarPlaneImageProps {
  planeName: string;
  imageUri: string;
  onPress: () => void;
}

/**
 * The desktop sidebar's always-visible plane card art, rotated 90° clockwise
 * (plane cards are printed landscape). Tapping opens the plane details.
 */
export function SidebarPlaneImage({ planeName, imageUri, onPress }: SidebarPlaneImageProps) {
  return (
    <TouchableOpacity
      style={styles.sidebarImageContainer}
      onPress={onPress}
      activeOpacity={0.8}
      accessibilityLabel={`View ${planeName} details`}
      accessibilityRole="button"
    >
      <Image source={{ uri: imageUri }} style={styles.sidebarPlaneImage} resizeMode="contain" />
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  sidebarImageContainer: {
    margin: 12,
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sidebarPlaneImage: {
    width: '73%',
    aspectRatio: 457 / 626,
    transform: [{ rotate: '90deg' }],
  },
});
