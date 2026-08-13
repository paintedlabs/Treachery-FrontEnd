import { useState, useEffect, useCallback } from 'react';
import { Timestamp } from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { TreacheryUser, FriendRequest } from '@/models/types';
import * as firestoreService from '@/services/firestore';
import { functions } from '@/config/firebase';
import { trackEvent } from '@/services/analytics';

interface UseFriendsReturn {
  friends: TreacheryUser[];
  pendingRequests: FriendRequest[];
  searchResults: TreacheryUser[];
  isLoading: boolean;
  isSearching: boolean;
  errorMessage: string | null;
  sentRequestUserIds: Set<string>;
  searchUsers: (name: string) => Promise<void>;
  sendRequest: (toUser: TreacheryUser) => Promise<void>;
  acceptRequest: (request: FriendRequest) => Promise<void>;
  declineRequest: (request: FriendRequest) => Promise<void>;
  removeFriend: (friend: TreacheryUser) => Promise<void>;
  isFriend: (user: TreacheryUser) => boolean;
  refresh: () => Promise<void>;
}

export function useFriends(userId: string | null): UseFriendsReturn {
  const [friends, setFriends] = useState<TreacheryUser[]>([]);
  const [pendingRequests, setPendingRequests] = useState<FriendRequest[]>([]);
  const [searchResults, setSearchResults] = useState<TreacheryUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSearching, setIsSearching] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [sentRequestUserIds, setSentRequestUserIds] = useState<Set<string>>(new Set());

  const loadData = useCallback(async () => {
    if (!userId) return;
    setIsLoading(true);
    setErrorMessage(null);

    try {
      const [fetchedFriends, fetchedRequests] = await Promise.all([
        firestoreService.getFriends(userId),
        firestoreService.getPendingFriendRequests(userId),
      ]);
      setFriends(fetchedFriends);
      setPendingRequests(fetchedRequests);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to load friends.');
    }
    setIsLoading(false);
  }, [userId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const searchUsersAction = useCallback(async (name: string) => {
    const trimmed = name.trim();
    if (!trimmed) return;
    setIsSearching(true);
    setErrorMessage(null);

    try {
      const results = await firestoreService.searchUsers(trimmed);
      setSearchResults(results);
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Search failed.');
    }
    setIsSearching(false);
  }, []);

  const sendRequest = useCallback(
    async (toUser: TreacheryUser) => {
      if (!userId) return;
      setErrorMessage(null);

      try {
        const currentUser = await firestoreService.getUser(userId);
        const request: FriendRequest = {
          id: generateId(),
          from_user_id: userId,
          from_display_name: currentUser?.display_name ?? 'Player',
          to_user_id: toUser.id,
          status: 'pending',
          created_at: Timestamp.now(),
        };
        await firestoreService.sendFriendRequest(request);
        setSentRequestUserIds((prev) => new Set(prev).add(toUser.id));
        trackEvent('send_friend_request');
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to send request.');
      }
    },
    [userId],
  );

  const acceptRequest = useCallback(
    async (request: FriendRequest) => {
      if (!userId) return;
      setErrorMessage(null);

      try {
        const acceptFn = httpsCallable(functions, 'acceptFriendRequest');
        await acceptFn({ requestId: request.id });
        trackEvent('accept_friend_request');
        await loadData();
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to accept request.');
      }
    },
    [userId, loadData],
  );

  const declineRequest = useCallback(async (request: FriendRequest) => {
    setErrorMessage(null);
    try {
      const updated: FriendRequest = { ...request, status: 'declined' };
      await firestoreService.updateFriendRequest(updated);
      setPendingRequests((prev) => prev.filter((r) => r.id !== request.id));
    } catch (error: unknown) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to decline request.');
    }
  }, []);

  // No UI entry point yet — exposed alongside acceptRequest so whatever adds a
  // "Remove friend" control gets the mutual (server-side) removal for free.
  const removeFriend = useCallback(
    async (friend: TreacheryUser) => {
      if (!userId) return;
      setErrorMessage(null);

      try {
        await firestoreService.removeFriend(friend.id);
        trackEvent('remove_friend');
        await loadData();
      } catch (error: unknown) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to remove friend.');
      }
    },
    [userId, loadData],
  );

  const isFriend = useCallback(
    (user: TreacheryUser) => friends.some((f) => f.id === user.id),
    [friends],
  );

  return {
    friends,
    pendingRequests,
    searchResults,
    isLoading,
    isSearching,
    errorMessage,
    sentRequestUserIds,
    searchUsers: searchUsersAction,
    sendRequest,
    acceptRequest,
    declineRequest,
    removeFriend,
    isFriend,
    refresh: loadData,
  };
}

function generateId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
