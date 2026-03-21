import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  ActivityIndicator,
} from 'react-native';
import { useAuth } from '@/hooks/useAuth';
import { useFriends } from '@/hooks/useFriends';
import { ErrorBanner } from '@/components/ErrorBanner';
import { colors, spacing, fonts } from '@/constants/theme';

export default function FriendsScreen() {
  const { currentUserId } = useAuth();
  const {
    friends,
    pendingRequests,
    searchResults,
    isLoading,
    isSearching,
    errorMessage,
    sentRequestUserIds,
    searchUsers,
    sendRequest,
    acceptRequest,
    declineRequest,
    isFriend,
  } = useFriends(currentUserId);

  const [searchText, setSearchText] = useState('');

  const handleSearch = () => {
    if (searchText.trim()) {
      searchUsers(searchText);
    }
  };

  return (
    <View style={styles.container}>
      {/* Search section */}
      <View style={styles.searchSection}>
        <Text style={styles.sectionTitle}>Add Friends</Text>
        <View style={styles.searchRow}>
          <TextInput
            style={styles.searchInput}
            placeholder="Search by display name"
            placeholderTextColor={colors.textTertiary}
            value={searchText}
            onChangeText={setSearchText}
            autoCapitalize="none"
            autoCorrect={false}
            onSubmitEditing={handleSearch}
            returnKeyType="search"
            accessibilityLabel="Search friends by display name"
            accessibilityRole="search"
          />
          {isSearching ? (
            <ActivityIndicator size="small" color={colors.primary} />
          ) : searchText.length > 0 ? (
            <TouchableOpacity
              onPress={handleSearch}
              accessibilityLabel="Search"
              accessibilityRole="button"
            >
              <Text style={styles.searchButton}>Search</Text>
            </TouchableOpacity>
          ) : null}
        </View>

        {/* Search results */}
        {searchResults
          .filter((u) => u.id !== currentUserId)
          .map((user) => (
            <View key={user.id} style={styles.resultRow}>
              <Text style={styles.userName}>{user.display_name}</Text>
              {isFriend(user) ? (
                <Text style={styles.friendsLabel}>Friends</Text>
              ) : sentRequestUserIds.has(user.id) ? (
                <Text style={styles.sentLabel}>Request Sent</Text>
              ) : (
                <TouchableOpacity
                  style={styles.addButton}
                  onPress={() => sendRequest(user)}
                  accessibilityLabel={`Send friend request to ${user.display_name}`}
                  accessibilityRole="button"
                >
                  <Text style={styles.addButtonText}>Add</Text>
                </TouchableOpacity>
              )}
            </View>
          ))}
      </View>

      {/* Pending requests */}
      {pendingRequests.length > 0 && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Friend Requests ({pendingRequests.length})</Text>
          {pendingRequests.map((request) => (
            <View key={request.id} style={styles.requestRow}>
              <View style={styles.requestInfo}>
                <Text style={styles.userName}>{request.from_display_name}</Text>
                <Text style={styles.subtitle}>Wants to be friends</Text>
              </View>
              <TouchableOpacity
                style={styles.acceptButton}
                onPress={() => acceptRequest(request)}
                accessibilityLabel={`Accept friend request from ${request.from_display_name}`}
                accessibilityRole="button"
              >
                <Text style={styles.acceptText}>Accept</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.declineButton}
                onPress={() => declineRequest(request)}
                accessibilityLabel={`Decline friend request from ${request.from_display_name}`}
                accessibilityRole="button"
              >
                <Text style={styles.declineText}>Decline</Text>
              </TouchableOpacity>
            </View>
          ))}
        </View>
      )}

      {/* Ornate divider */}
      <View style={styles.ornateDivider}>
        <View style={styles.ornateLine} />
        <Text style={styles.ornateDiamond}>&#9670;</Text>
        <View style={styles.ornateLine} />
      </View>

      {/* Friends list */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Friends ({friends.length})</Text>
        {isLoading ? (
          <ActivityIndicator color={colors.primary} style={{ padding: 16 }} />
        ) : friends.length === 0 ? (
          <Text style={styles.emptyText}>No friends yet. Search for players above.</Text>
        ) : (
          <FlatList
            data={friends}
            keyExtractor={(f) => f.id}
            renderItem={({ item }) => (
              <View style={styles.friendRow}>
                <View style={styles.friendIcon}>
                  <Text style={styles.friendInitial}>
                    {item.display_name?.charAt(0)?.toUpperCase() ?? '?'}
                  </Text>
                </View>
                <Text style={styles.friendName}>{item.display_name}</Text>
              </View>
            )}
            style={styles.list}
          />
        )}
      </View>

      {errorMessage && <ErrorBanner message={errorMessage} />}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  searchSection: {
    padding: spacing.lg,
    gap: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  section: {
    padding: spacing.lg,
    gap: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  searchInput: {
    flex: 1,
    backgroundColor: colors.surface,
    color: colors.text,
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  searchButton: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  resultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
  },
  userName: {
    color: colors.text,
    fontSize: 16,
    flex: 1,
  },
  friendsLabel: {
    color: colors.success,
    fontSize: 12,
    fontWeight: '500',
  },
  sentLabel: {
    color: colors.warning,
    fontSize: 12,
    fontStyle: 'italic',
  },
  addButton: {
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: 6,
    paddingHorizontal: 12,
    paddingVertical: 4,
  },
  addButtonText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '600',
  },
  requestRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    gap: 8,
  },
  requestInfo: {
    flex: 1,
  },
  subtitle: {
    color: colors.textTertiary,
    fontSize: 12,
    fontStyle: 'italic',
  },
  acceptButton: {
    backgroundColor: colors.primary,
    borderRadius: 6,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  acceptText: {
    color: '#0d0b1a',
    fontSize: 12,
    fontWeight: '700',
  },
  declineButton: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 6,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  declineText: {
    color: colors.textSecondary,
    fontSize: 12,
  },
  ornateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    gap: 12,
  },
  ornateLine: {
    flex: 1,
    height: 1,
    backgroundColor: colors.border,
  },
  ornateDiamond: {
    color: colors.primary,
    fontSize: 10,
  },
  emptyText: {
    color: colors.textTertiary,
    fontSize: 14,
    padding: spacing.sm,
    fontStyle: 'italic',
  },
  list: {
    maxHeight: 400,
  },
  friendRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    gap: 10,
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  friendIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  friendInitial: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '600',
    fontFamily: fonts.serif,
  },
  friendName: {
    color: colors.text,
    fontSize: 16,
  },
});
