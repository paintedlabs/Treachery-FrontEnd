import { Role } from '@/models/types';

export const ROLE_DISPLAY_NAMES: Record<Role, string> = {
  leader: 'Leader',
  guardian: 'Guardian',
  assassin: 'Assassin',
  traitor: 'Traitor',
};

export const ROLE_COLORS: Record<Role, string> = {
  leader: '#e4c96a', // Royal gold
  guardian: '#4c8cc9', // Arcane blue
  assassin: '#c94c4c', // Blood red
  traitor: '#9c4cc9', // Shadow purple
};

export const ROLE_WIN_CONDITIONS: Record<Role, string> = {
  leader: 'Eliminate all Assassins and Traitors to win.',
  guardian: 'Keep the Leader alive. Eliminate all Assassins and Traitors.',
  assassin: 'Eliminate the Leader while at least one Assassin survives.',
  traitor: 'Be the last player standing.',
};

export const RARITY_DISPLAY_NAMES: Record<string, string> = {
  uncommon: 'Uncommon',
  rare: 'Rare',
  mythic: 'Mythic',
  special: 'Special',
};

export const RARITY_COLORS: Record<string, string> = {
  uncommon: '#3ca85c',
  rare: '#4c8cc9',
  mythic: '#d4943c',
  special: '#9c4cc9',
};

export interface RoleDistribution {
  leaders: number;
  guardians: number;
  assassins: number;
  traitors: number;
}

export function getRoleDistribution(playerCount: number): RoleDistribution {
  switch (playerCount) {
    case 1:
      return { leaders: 1, guardians: 0, assassins: 0, traitors: 0 };
    case 2:
      return { leaders: 1, guardians: 0, assassins: 1, traitors: 0 };
    case 3:
      return { leaders: 1, guardians: 0, assassins: 1, traitors: 1 };
    case 4:
      return { leaders: 1, guardians: 0, assassins: 2, traitors: 1 };
    case 5:
      return { leaders: 1, guardians: 1, assassins: 2, traitors: 1 };
    case 6:
      return { leaders: 1, guardians: 1, assassins: 3, traitors: 1 };
    case 7:
      return { leaders: 1, guardians: 2, assassins: 3, traitors: 1 };
    case 8:
      return { leaders: 1, guardians: 2, assassins: 3, traitors: 2 };
    default:
      return { leaders: 1, guardians: 0, assassins: 2, traitors: 1 };
  }
}

export const MINIMUM_PLAYER_COUNT = __DEV__ ? 1 : 4;

// Characters for game code generation (excludes ambiguous: I, O, 0, 1)
export const CODE_CHARACTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
