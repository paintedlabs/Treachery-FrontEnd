import { useState, useEffect, useCallback } from 'react';
import { Timestamp } from 'firebase/firestore';
import { TreacheryUser, FriendRequest } from '@/models/types';
import * as firestoreService from '@/services/firestore';

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
    } catch (error: any) {
      setErrorMessage(error.message || 'Failed to load friends.');
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
    } catch (error: any) {
      setErrorMessage(error.message || 'Search failed.');
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
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to send request.');
      }
    },
    [userId]
  );

  const acceptRequest = useCallback(
    async (request: FriendRequest) => {
      if (!userId) return;
      setErrorMessage(null);

      try {
        const updated: FriendRequest = { ...request, status: 'accepted' };
        await firestoreService.updateFriendRequest(updated);
        await firestoreService.addFriend(userId, request.from_user_id);
        await loadData();
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to accept request.');
      }
    },
    [userId, loadData]
  );

  const declineRequest = useCallback(
    async (request: FriendRequest) => {
      setErrorMessage(null);
      try {
        const updated: FriendRequest = { ...request, status: 'declined' };
        await firestoreService.updateFriendRequest(updated);
        setPendingRequests((prev) => prev.filter((r) => r.id !== request.id));
      } catch (error: any) {
        setErrorMessage(error.message || 'Failed to decline request.');
      }
    },
    []
  );

  const isFriend = useCallback(
    (user: TreacheryUser) => friends.some((f) => f.id === user.id),
    [friends]
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
