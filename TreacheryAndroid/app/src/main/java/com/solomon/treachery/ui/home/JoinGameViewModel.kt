package com.solomon.treachery.ui.home

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
class JoinGameViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _isJoining = MutableStateFlow(false)
    val isJoining: StateFlow<Boolean> = _isJoining.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun joinGame(
        userId: String,
        gameCode: String,
        onSuccess: (gameId: String, isHost: Boolean) -> Unit
    ) {
        _isJoining.value = true
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val game = firestoreRepository.getGameByCode(gameCode)
                    ?: throw IllegalStateException("No game found with that code.")

                if (game.state != GameState.WAITING) {
                    throw IllegalStateException("This game has already started.")
                }

                val existingPlayers = firestoreRepository.getPlayers(game.id)

                if (existingPlayers.size >= game.maxPlayers) {
                    throw IllegalStateException("This game is full.")
                }

                // Already in game? Just navigate
                if (existingPlayers.any { it.userId == userId }) {
                    onSuccess(game.id, false)
                    _isJoining.value = false
                    return@launch
                }

                val user = firestoreRepository.getUser(userId)
                val player = Player(
                    id = UUID.randomUUID().toString(),
                    orderId = existingPlayers.size,
                    userId = userId,
                    displayName = user?.displayName ?: "Player",
                    lifeTotal = game.startingLife,
                    joinedAt = Timestamp.now()
                )
                firestoreRepository.addPlayer(player, game.id)
                firestoreRepository.addPlayerIdToGame(game.id, userId)

                AnalyticsService.trackEvent("join_game")
                onSuccess(game.id, false)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "Failed to join game"
            }
            _isJoining.value = false
        }
    }
}
