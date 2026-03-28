import { useWindowDimensions, Platform } from 'react-native';
import { breakpoints, contentMaxWidths } from '@/constants/theme';

export type Breakpoint = 'mobile' | 'tablet' | 'desktop';

export interface ResponsiveInfo {
  breakpoint: Breakpoint;
  width: number;
  isMobile: boolean;
  isTablet: boolean;
  isDesktop: boolean;
}

export function useResponsive(): ResponsiveInfo {
  const { width } = useWindowDimensions();

  // Native always returns mobile — desktop layout is web-only
  if (Platform.OS !== 'web') {
    return {
      breakpoint: 'mobile',
      width,
      isMobile: true,
      isTablet: false,
      isDesktop: false,
    };
  }

  const breakpoint: Breakpoint =
    width >= breakpoints.desktop
      ? 'desktop'
      : width >= breakpoints.tablet
        ? 'tablet'
        : 'mobile';

  return {
    breakpoint,
    width,
    isMobile: breakpoint === 'mobile',
    isTablet: breakpoint === 'tablet',
    isDesktop: breakpoint === 'desktop',
  };
}
