package com.solomon.treachery.ui.lobby

import androidx.lifecycle.SavedStateHandle
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
class LobbyViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository,
    private val cloudFunctionsRepository: CloudFunctionsRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    val gameId: String = savedStateHandle["gameId"] ?: ""
    private val navIsHost: Boolean = savedStateHandle["isHost"] ?: false

    private val _game = MutableStateFlow<Game?>(null)
    val game: StateFlow<Game?> = _game.asStateFlow()

    private val _players = MutableStateFlow<List<Player>>(emptyList())
    val players: StateFlow<List<Player>> = _players.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isStartingGame = MutableStateFlow(false)
    val isStartingGame: StateFlow<Boolean> = _isStartingGame.asStateFlow()

    private val _isGameDisbanded = MutableStateFlow(false)
    val isGameDisbanded: StateFlow<Boolean> = _isGameDisbanded.asStateFlow()

    // The Game model does not surface max_traitor_rarity yet, so track the
    // host's selection locally, seeded from what this session last sent the
    // server (falling back to the server default of allowing every traitor).
    private val _maxTraitorRarity = MutableStateFlow(
        cloudFunctionsRepository.lastKnownMaxTraitorRarity(gameId)
            ?.let { Rarity.fromValue(it) } ?: Rarity.SPECIAL
    )
    val maxTraitorRarity: StateFlow<Rarity> = _maxTraitorRarity.asStateFlow()

    var currentUserId: String? = null

    private var hasReceivedFirstSnapshot = false

    val currentPlayer: Player?
        get() = currentUserId?.let { uid -> players.value.find { it.userId == uid } }

    /** True when the signed-in user is the live host (updates after host promotion). */
    val isHost: Boolean
        get() {
            val uid = currentUserId ?: return navIsHost
            val hostId = game.value?.hostId
            return if (hostId != null) hostId == uid else navIsHost
        }

    val canStartGame: Boolean
        get() {
            val g = game.value ?: return false
            val minPlayers = if (g.gameMode.includesTreachery) Role.MINIMUM_PLAYER_COUNT else 1
            return isHost && players.value.size >= minPlayers
        }

    val minimumPlayerCount: Int
        get() {
            val g = game.value ?: return Role.MINIMUM_PLAYER_COUNT
            return if (g.gameMode.includesTreachery) Role.MINIMUM_PLAYER_COUNT else 1
        }

    val isGameStarted: Boolean
        get() = game.value?.state == GameState.IN_PROGRESS

    init {
        startListening()
    }

    private fun startListening() {
        viewModelScope.launch {
            firestoreRepository.gameFlow(gameId).collect { game ->
                if (game == null && hasReceivedFirstSnapshot) {
                    _isGameDisbanded.value = true
                }
                _game.value = game
                hasReceivedFirstSnapshot = true
            }
        }
        viewModelScope.launch {
            firestoreRepository.playersFlow(gameId).collect { playerList ->
                _players.value = playerList
            }
        }
    }

    fun startGame() {
        if (!isHost) return
        _errorMessage.value = null
        _isStartingGame.value = true
        viewModelScope.launch {
            try {
                cloudFunctionsRepository.startGame(gameId)
                AnalyticsService.trackEvent("start_game", mapOf(
                    "player_count" to players.value.size.toString(),
                    "game_mode" to (game.value?.gameMode?.value ?: "unknown")
                ))
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isStartingGame.value = false
        }
    }

    fun leaveGame() {
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                cloudFunctionsRepository.leaveGame(gameId)
                AnalyticsService.trackEvent("leave_lobby")
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun updatePlayerColor(hex: String?) {
        val player = currentPlayer ?: return
        viewModelScope.launch {
            try {
                firestoreRepository.updatePlayerColor(gameId, player.id, hex)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun updateCommanderName(name: String?) {
        val player = currentPlayer ?: return
        viewModelScope.launch {
            try {
                firestoreRepository.updateCommanderName(gameId, player.id, name)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun updateGameSettings(maxPlayers: Int? = null, startingLife: Int? = null, gameMode: String? = null, maxTraitorRarity: String? = null) {
        if (!isHost) return
        viewModelScope.launch {
            try {
                cloudFunctionsRepository.updateGameSettings(gameId, maxPlayers, startingLife, gameMode, maxTraitorRarity)
                // The game doc flow echoes the other settings back, but rarity
                // is tracked locally (see _maxTraitorRarity above).
                maxTraitorRarity?.let { value ->
                    Rarity.fromValue(value)?.let { _maxTraitorRarity.value = it }
                }
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

}
