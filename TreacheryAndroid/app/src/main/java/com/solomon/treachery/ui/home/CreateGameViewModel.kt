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
class CreateGameViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _isCreating = MutableStateFlow(false)
    val isCreating: StateFlow<Boolean> = _isCreating.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun createGame(
        userId: String,
        gameMode: GameMode,
        startingLife: Int,
        useOwnDeck: Boolean,
        onSuccess: (gameId: String) -> Unit
    ) {
        _isCreating.value = true
        _errorMessage.value = null

        val maxPlayers = if (gameMode.includesTreachery) 8 else 12

        viewModelScope.launch {
            try {
                val code = generateUniqueCode()
                val gameId = UUID.randomUUID().toString()
                val now = Timestamp.now()
                val game = Game(
                    id = gameId,
                    code = code,
                    hostId = userId,
                    state = GameState.WAITING,
                    gameMode = gameMode,
                    maxPlayers = maxPlayers,
                    startingLife = startingLife,
                    playerIds = listOf(userId),
                    createdAt = now,
                    lastActivityAt = now,
                    planechase = if (gameMode.includesPlanechase) PlanechaseState(
                        useOwnDeck = useOwnDeck
                    ) else null
                )
                firestoreRepository.createGame(game)

                val user = firestoreRepository.getUser(userId)
                val player = Player(
                    id = UUID.randomUUID().toString(),
                    orderId = 0,
                    userId = userId,
                    displayName = user?.displayName ?: "Host",
                    lifeTotal = startingLife,
                    joinedAt = now
                )
                firestoreRepository.addPlayer(player, gameId)

                AnalyticsService.trackEvent("create_game", mapOf("game_mode" to gameMode.value))
                onSuccess(gameId)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "Failed to create game"
            }
            _isCreating.value = false
        }
    }

    private suspend fun generateUniqueCode(): String {
        val characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        repeat(10) {
            val code = (1..4).map { characters.random() }.joinToString("")
            val existing = firestoreRepository.getGameByCode(code)
            if (existing == null) return code
        }
        throw IllegalStateException("Could not generate a unique game code. Please try again.")
    }
}
