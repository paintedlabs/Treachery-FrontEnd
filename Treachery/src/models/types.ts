import { Timestamp } from 'firebase/firestore';

// Enums matching iOS raw values exactly

export type Role = 'leader' | 'guardian' | 'assassin' | 'traitor';
export type GameState = 'waiting' | 'in_progress' | 'finished';
export type Rarity = 'uncommon' | 'rare' | 'mythic' | 'special';
export type FriendRequestStatus = 'pending' | 'accepted' | 'declined';

// Game modes
export type GameMode = 'treachery' | 'planechase' | 'treachery_planechase' | 'none';

// Planechase state (subdocument on Game)
export interface PlanechaseState {
  use_own_deck: boolean;
  current_plane_id: string | null;
  used_plane_ids: string[];
  last_die_roller_id: string | null;
  die_roll_count: number;
  chaotic_aether_active?: boolean;
  secondary_plane_id?: string;
}

// Plane card from bundled PlaneCards.json
export interface PlaneCard {
  id: string;
  name: string;
  type_line: string;
  oracle_text: string;
  image_uri: string | null;
  is_phenomenon: boolean;
}

// Firestore document interfaces — field names use snake_case to match existing iOS data

export interface DeckStat {
  elo: number;
  wins: number;
  losses: number;
  games: number;
}

export interface TreacheryUser {
  id: string;
  display_name: string;
  email: string | null;
  phone_number: string | null;
  friend_ids: string[];
  fcm_token?: string | null;
  created_at: Timestamp;
  elo?: number;
  deck_stats?: Record<string, DeckStat>;
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
  game_mode?: GameMode;
  planechase?: PlanechaseState;
  winner_user_ids?: string[];
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
  player_color: string | null;
  commander_name: string | null;
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
