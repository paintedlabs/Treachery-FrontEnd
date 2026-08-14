import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  orderBy,
  limit,
  onSnapshot,
  arrayUnion,
  documentId,
  Unsubscribe,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from '@/config/firebase';
import { TreacheryUser, Game, Player, FriendRequest } from '@/models/types';

// ── Collection references ──

const usersCol = () => collection(db, 'users');
const gamesCol = () => collection(db, 'games');
const playersCol = (gameId: string) => collection(db, 'games', gameId, 'players');
const friendRequestsCol = () => collection(db, 'friend_requests');

// ── Users ──

export async function createUser(user: TreacheryUser): Promise<void> {
  // Public profile only — PII goes under users/{id}/private/data
  await setDoc(doc(usersCol(), user.id), {
    id: user.id,
    display_name: user.display_name,
    friend_ids: user.friend_ids ?? [],
    created_at: user.created_at,
    ...(user.elo !== undefined ? { elo: user.elo } : {}),
    ...(user.deck_stats ? { deck_stats: user.deck_stats } : {}),
  });

  const privateData: Record<string, string> = {};
  if (user.email) privateData.email = user.email;
  if (user.phone_number) privateData.phone_number = user.phone_number;
  const fcm = (user as TreacheryUser & { fcm_token?: string | null }).fcm_token;
  if (fcm) privateData.fcm_token = fcm;
  if (Object.keys(privateData).length > 0) {
    await setDoc(doc(usersCol(), user.id, 'private', 'data'), privateData, { merge: true });
  }
}

export async function getUser(id: string): Promise<TreacheryUser | null> {
  const snap = await getDoc(doc(usersCol(), id));
  if (!snap.exists()) return null;
  return { ...snap.data(), id: snap.id } as TreacheryUser;
}

export async function updateUser(user: TreacheryUser): Promise<void> {
  await setDoc(
    doc(usersCol(), user.id),
    {
      id: user.id,
      display_name: user.display_name,
      friend_ids: user.friend_ids ?? [],
      created_at: user.created_at,
      ...(user.elo !== undefined ? { elo: user.elo } : {}),
      ...(user.deck_stats ? { deck_stats: user.deck_stats } : {}),
    },
    { merge: true },
  );
}

export async function searchUsers(name: string): Promise<TreacheryUser[]> {
  const end = name + '\uf8ff';
  const q = query(
    usersCol(),
    where('display_name', '>=', name),
    where('display_name', '<', end),
    limit(20),
  );
  const snap = await getDocs(q);
  return snap.docs.map((d) => ({ ...d.data(), id: d.id }) as TreacheryUser);
}

// ── Friend Requests ──

export async function sendFriendRequest(request: FriendRequest): Promise<void> {
  await setDoc(doc(friendRequestsCol(), request.id), request);
}

export async function getPendingFriendRequests(userId: string): Promise<FriendRequest[]> {
  const q = query(
    friendRequestsCol(),
    where('to_user_id', '==', userId),
    where('status', '==', 'pending'),
  );
  const snap = await getDocs(q);
  return snap.docs.map((d) => ({ ...d.data(), id: d.id }) as FriendRequest);
}

export async function updateFriendRequest(request: FriendRequest): Promise<void> {
  await setDoc(doc(friendRequestsCol(), request.id), request, { merge: true });
}

export async function addFriend(userId: string, friendId: string): Promise<void> {
  // Mutual friendship is established via acceptFriendRequest callable.
  await updateDoc(doc(usersCol(), userId), {
    friend_ids: arrayUnion(friendId),
  });
}

export async function removeFriend(friendId: string): Promise<void> {
  // Must go through the callable: rules deny writing another user's doc, so a
  // client-side remove would leave the friendship intact on their side. The
  // caller's uid comes from the auth context server-side.
  const removeFn = httpsCallable(functions, 'removeFriend');
  await removeFn({ friendId });
}

export async function getFriends(userId: string): Promise<TreacheryUser[]> {
  const user = await getUser(userId);
  if (!user || !user.friend_ids || user.friend_ids.length === 0) return [];

  // Firestore 'in' queries limited to 30 items — run all chunks in parallel
  const chunks: string[][] = [];
  for (let i = 0; i < user.friend_ids.length; i += 30) {
    chunks.push(user.friend_ids.slice(i, i + 30));
  }

  const results = await Promise.all(
    chunks.map((chunk) => getDocs(query(usersCol(), where(documentId(), 'in', chunk)))),
  );

  const friends = results.flatMap((snap) => snap.docs.map((d) => ({ ...d.data(), id: d.id }) as TreacheryUser));
  return friends.sort((a, b) => a.display_name.localeCompare(b.display_name));
}

// ── Games ──

export async function createGame(game: Game): Promise<void> {
  await setDoc(doc(gamesCol(), game.id), game);
}

export async function getGame(id: string): Promise<Game | null> {
  const snap = await getDoc(doc(gamesCol(), id));
  if (!snap.exists()) return null;
  return { ...snap.data(), id: snap.id } as Game;
}

export async function getGameByCode(code: string): Promise<Game | null> {
  const q = query(gamesCol(), where('code', '==', code), limit(1));
  const snap = await getDocs(q);
  if (snap.empty) return null;
  const d = snap.docs[0];
  return { ...d.data(), id: d.id } as Game;
}

export async function updateGame(game: Game): Promise<void> {
  await setDoc(doc(gamesCol(), game.id), game, { merge: true });
}

export async function deleteGame(id: string): Promise<void> {
  await deleteDoc(doc(gamesCol(), id));
}

export async function addPlayerIdToGame(gameId: string, userId: string): Promise<void> {
  await updateDoc(doc(gamesCol(), gameId), {
    player_ids: arrayUnion(userId),
  });
}

export async function getActiveGame(userId: string): Promise<Game | null> {
  // Check for in_progress games
  const inProgressQ = query(
    gamesCol(),
    where('player_ids', 'array-contains', userId),
    where('state', '==', 'in_progress'),
    limit(1),
  );
  const inProgressSnap = await getDocs(inProgressQ);
  if (!inProgressSnap.empty) {
    const d = inProgressSnap.docs[0];
    return { ...d.data(), id: d.id } as Game;
  }

  // Check for waiting games (lobby)
  const waitingQ = query(
    gamesCol(),
    where('player_ids', 'array-contains', userId),
    where('state', '==', 'waiting'),
    limit(1),
  );
  const waitingSnap = await getDocs(waitingQ);
  if (!waitingSnap.empty) {
    const d = waitingSnap.docs[0];
    return { ...d.data(), id: d.id } as Game;
  }

  return null;
}

export async function getFinishedGames(userId: string): Promise<Game[]> {
  const q = query(
    gamesCol(),
    where('player_ids', 'array-contains', userId),
    where('state', '==', 'finished'),
    orderBy('created_at', 'desc'),
    limit(50),
  );
  const snap = await getDocs(q);
  return snap.docs.map((d) => ({ ...d.data(), id: d.id }) as Game);
}

export function listenToGame(id: string, onChange: (game: Game | null) => void): Unsubscribe {
  return onSnapshot(doc(gamesCol(), id), (snap) => {
    if (!snap.exists()) {
      onChange(null);
      return;
    }
    onChange({ ...snap.data(), id: snap.id } as Game);
  });
}

// ── Players ──

export async function addPlayer(player: Player, gameId: string): Promise<void> {
  await setDoc(doc(playersCol(gameId), player.id), player);
}

export async function getPlayers(gameId: string): Promise<Player[]> {
  const q = query(playersCol(gameId), orderBy('order_id'));
  const snap = await getDocs(q);
  return snap.docs.map((d) => ({ ...d.data(), id: d.id }) as Player);
}

export async function updatePlayer(player: Player, gameId: string): Promise<void> {
  await setDoc(doc(playersCol(gameId), player.id), player, { merge: true });
}

export async function removePlayer(id: string, gameId: string): Promise<void> {
  await deleteDoc(doc(playersCol(gameId), id));
}

export function listenToPlayers(
  gameId: string,
  onChange: (players: Player[]) => void,
): Unsubscribe {
  const q = query(playersCol(gameId), orderBy('order_id'));
  return onSnapshot(q, (snap) => {
    const players = snap.docs.map((d) => ({ ...d.data(), id: d.id }) as Player);
    onChange(players);
  });
}

export async function updatePlayerColor(
  gameId: string,
  playerId: string,
  color: string | null,
): Promise<void> {
  const ref = doc(db, 'games', gameId, 'players', playerId);
  await updateDoc(ref, { player_color: color });
}

export async function updateCommanderName(
  gameId: string,
  playerId: string,
  name: string | null,
): Promise<void> {
  const ref = doc(db, 'games', gameId, 'players', playerId);
  await updateDoc(ref, { commander_name: name && name.trim() ? name.trim() : null });
}

export async function updatePlayerDisplayName(
  gameId: string,
  playerId: string,
  name: string,
): Promise<void> {
  const ref = doc(db, 'games', gameId, 'players', playerId);
  await updateDoc(ref, { display_name: name });
}

export async function updateUserDisplayName(userId: string, name: string): Promise<void> {
  await updateDoc(doc(db, 'users', userId), { display_name: name });
}

