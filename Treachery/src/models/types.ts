import { Timestamp } from 'firebase/firestore';

// Enums matching iOS raw values exactly

export type Role = 'leader' | 'guardian' | 'assassin' | 'traitor';
export type GameState = 'waiting' | 'in_progress' | 'finished';
export type Rarity = 'uncommon' | 'rare' | 'mythic' | 'special';
export type FriendRequestStatus = 'pending' | 'accepted' | 'declined';

// Firestore document interfaces — field names use snake_case to match existing iOS data

export interface TreacheryUser {
  id: string;
  display_name: string;
  email: string | null;
  phone_number: string | null;
  friend_ids: string[];
  fcm_token?: string | null;
  created_at: Timestamp;
}

export interface Game {
  id: string;
  code: string;
  host_id: string;
  state: GameState;
  max_players: number;
  starting_life: number;
  winning_team: string | null;
  player_ids: string[];
  created_at: Timestamp;
  last_activity_at?: Timestamp;
}

export interface Player {
  id: string;
  order_id: number;
  user_id: string;
  display_name: string;
  role: Role | null;
  identity_card_id: string | null;
  life_total: number;
  is_eliminated: boolean;
  is_unveiled: boolean;
  joined_at: Timestamp;
}

export interface IdentityCard {
  id: string;
  card_number: number;
  name: string;
  role: Role;
  ability_text: string;
  unveil_cost: string;
  rarity: Rarity;
  has_undercover: boolean;
  undercover_condition: string | null;
  timing_restriction: string | null;
  life_modifier: number | null;
  hand_size_modifier: number | null;
  flavor_text: string | null;
  image_asset_name: string | null;
}

export interface FriendRequest {
  id: string;
  from_user_id: string;
  from_display_name: string;
  to_user_id: string;
  status: FriendRequestStatus;
  created_at: Timestamp;
}
