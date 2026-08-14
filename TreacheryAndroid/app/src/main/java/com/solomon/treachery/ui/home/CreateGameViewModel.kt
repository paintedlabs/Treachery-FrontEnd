package com.solomon.treachery.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.data.CloudFunctionsRepository
import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.model.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class CreateGameViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository,
    private val cloudFunctionsRepository: CloudFunctionsRepository
) : ViewModel() {

    private val _isCreating = MutableStateFlow(false)
    val isCreating: StateFlow<Boolean> = _isCreating.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun createGame(
        userId: String,
        gameMode: GameMode,
        startingLife: Int,
        maxTraitorRarity: Rarity,
        useOwnDeck: Boolean,
        onSuccess: (gameId: String) -> Unit
    ) {
        _isCreating.value = true
        _errorMessage.value = null

        val maxPlayers = 8

        viewModelScope.launch {
            try {
                val user = firestoreRepository.getUser(userId)
                val gameId = cloudFunctionsRepository.createGame(
                    gameMode = gameMode.value,
                    maxPlayers = maxPlayers,
                    startingLife = startingLife,
                    // Rarity only applies to treachery modes; omit it otherwise.
                    maxTraitorRarity = if (gameMode.includesTreachery) maxTraitorRarity.value else null,
                    useOwnDeck = useOwnDeck,
                    displayName = user?.displayName
                )

                AnalyticsService.trackEvent("create_game", mapOf("game_mode" to gameMode.value))
                onSuccess(gameId)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "Failed to create game"
            }
            _isCreating.value = false
        }
    }
}
