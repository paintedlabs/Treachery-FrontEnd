package com.solomon.treachery.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.Timestamp
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.model.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

@HiltViewModel
class FriendsViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _friends = MutableStateFlow<List<TreacheryUser>>(emptyList())
    val friends: StateFlow<List<TreacheryUser>> = _friends.asStateFlow()

    private val _pendingRequests = MutableStateFlow<List<FriendRequest>>(emptyList())
    val pendingRequests: StateFlow<List<FriendRequest>> = _pendingRequests.asStateFlow()

    private val _searchResults = MutableStateFlow<List<TreacheryUser>>(emptyList())
    val searchResults: StateFlow<List<TreacheryUser>> = _searchResults.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _sentRequestUserIds = MutableStateFlow<Set<String>>(emptySet())
    val sentRequestUserIds: StateFlow<Set<String>> = _sentRequestUserIds.asStateFlow()

    fun loadData(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                _friends.value = firestoreRepository.getFriends(userId)
                _pendingRequests.value = firestoreRepository.getPendingFriendRequests(userId)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isLoading.value = false
        }
    }

    fun searchUsers(query: String) {
        if (query.isBlank()) return
        _isSearching.value = true
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                _searchResults.value = firestoreRepository.searchUsers(query.trim())
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isSearching.value = false
        }
    }

    fun sendRequest(fromUserId: String, toUser: TreacheryUser) {
        viewModelScope.launch {
            _errorMessage.value = null
            try {
                val currentUser = firestoreRepository.getUser(fromUserId)
                val request = FriendRequest(
                    id = UUID.randomUUID().toString(),
                    fromUserId = fromUserId,
                    fromDisplayName = currentUser?.displayName ?: "Player",
                    toUserId = toUser.id,
                    status = FriendRequestStatus.PENDING,
                    createdAt = Timestamp.now()
                )
                firestoreRepository.sendFriendRequest(request)
                AnalyticsService.trackEvent("send_friend_request")
                _sentRequestUserIds.value = _sentRequestUserIds.value + toUser.id
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun acceptRequest(userId: String, request: FriendRequest) {
        viewModelScope.launch {
            _errorMessage.value = null
            try {
                val updated = FriendRequest(
                    id = request.id,
                    fromUserId = request.fromUserId,
                    fromDisplayName = request.fromDisplayName,
                    toUserId = request.toUserId,
                    status = FriendRequestStatus.ACCEPTED,
                    createdAt = request.createdAt
                )
                firestoreRepository.updateFriendRequest(updated)
                firestoreRepository.addFriend(userId, request.fromUserId)
                AnalyticsService.trackEvent("accept_friend_request")
                loadData(userId)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun declineRequest(request: FriendRequest) {
        viewModelScope.launch {
            _errorMessage.value = null
            try {
                val updated = FriendRequest(
                    id = request.id,
                    fromUserId = request.fromUserId,
                    fromDisplayName = request.fromDisplayName,
                    toUserId = request.toUserId,
                    status = FriendRequestStatus.DECLINED,
                    createdAt = request.createdAt
                )
                firestoreRepository.updateFriendRequest(updated)
                _pendingRequests.value = _pendingRequests.value.filter { it.id != request.id }
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun isFriend(userId: String): Boolean = friends.value.any { it.id == userId }
}
