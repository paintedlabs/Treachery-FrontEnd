package com.solomon.treachery.ui.game

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.solomon.treachery.data.*
import com.solomon.treachery.model.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class GameBoardViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository,
    private val cloudFunctionsRepository: CloudFunctionsRepository,
    private val cardDatabase: CardDatabase,
    private val planeDatabase: PlaneDatabase,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    val gameId: String = savedStateHandle["gameId"] ?: ""

    // Published state
    private val _game = MutableStateFlow<Game?>(null)
    val game: StateFlow<Game?> = _game.asStateFlow()

    private val _players = MutableStateFlow<List<Player>>(emptyList())
    val players: StateFlow<List<Player>> = _players.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isGameUnavailable = MutableStateFlow(false)
    val isGameUnavailable: StateFlow<Boolean> = _isGameUnavailable.asStateFlow()

    private val _isPending = MutableStateFlow(false)
    val isPending: StateFlow<Boolean> = _isPending.asStateFlow()

    // Planechase transient state
    private val _dieRollResult = MutableStateFlow<String?>(null)
    val dieRollResult: StateFlow<String?> = _dieRollResult.asStateFlow()

    private val _isRollingDie = MutableStateFlow(false)
    val isRollingDie: StateFlow<Boolean> = _isRollingDie.asStateFlow()

    private val _tunnelOptions = MutableStateFlow<List<PlaneCard>?>(null)
    val tunnelOptions: StateFlow<List<PlaneCard>?> = _tunnelOptions.asStateFlow()

    // Optimistic life tracking
    private val lifeDeltas = mutableMapOf<String, Int>()
    private val debounceJobs = mutableMapOf<String, Job>()
    private var serverPlayers: List<Player> = emptyList()

    var currentUserId: String? = null
    private var hasReceivedFirstGameSnapshot = false

    // Computed properties
    val currentPlayer: Player?
        get() = currentUserId?.let { uid -> players.value.find { it.userId == uid } }

    fun currentIdentityCard(): IdentityCard? {
        val cardId = currentPlayer?.identityCardId ?: return null
        return cardDatabase.card(cardId)
    }

    val isGameFinished: Boolean
        get() = game.value?.state == GameState.FINISHED

    val winningTeam: Role?
        get() = game.value?.winningTeam?.let { Role.fromValue(it) }

    val alivePlayers: List<Player>
        get() = players.value.filter { !it.isEliminated }

    val isPlanechaseActive: Boolean
        get() = game.value?.gameMode?.includesPlanechase ?: false

    val isTreacheryActive: Boolean
        get() = game.value?.gameMode?.includesTreachery ?: false

    val isOwnDeckMode: Boolean
        get() = game.value?.planechase?.useOwnDeck ?: false

    val isHost: Boolean
        get() = currentUserId != null && game.value?.hostId == currentUserId

    val currentPlane: PlaneCard?
        get() = game.value?.planechase?.currentPlaneId?.let { planeDatabase.plane(it) }

    val secondaryPlane: PlaneCard?
        get() = game.value?.planechase?.secondaryPlaneId?.let { planeDatabase.plane(it) }

    val isChaoticAetherActive: Boolean
        get() = game.value?.planechase?.chaoticAetherActive ?: false

    val dieRollCost: Int
        get() = maxOf(0, (game.value?.planechase?.dieRollCount ?: 0) - 1)

    val lastDieRollerName: String?
        get() {
            val rollerId = game.value?.planechase?.lastDieRollerId ?: return null
            return players.value.find { it.userId == rollerId }?.displayName
        }

    init {
        startListening()
    }

    override fun onCleared() {
        super.onCleared()
        debounceJobs.values.forEach { it.cancel() }
    }

    private fun startListening() {
        viewModelScope.launch {
            firestoreRepository.gameFlow(gameId).collect { game ->
                if (game == null && hasReceivedFirstGameSnapshot) {
                    _isGameUnavailable.value = true
                }
                _game.value = game
                hasReceivedFirstGameSnapshot = true
            }
        }
        viewModelScope.launch {
            firestoreRepository.playersFlow(gameId).collect { playerList ->
                serverPlayers = playerList
                applyOptimisticDeltas()
            }
        }
    }

    private fun applyOptimisticDeltas() {
        _players.value = serverPlayers.map { player ->
            val delta = lifeDeltas[player.id] ?: 0
            if (delta != 0) player.copy(lifeTotal = maxOf(0, player.lifeTotal + delta))
            else player
        }
    }

    // Life adjustment with optimistic update and 500ms debounce
    fun adjustLife(playerId: String, amount: Int) {
        val player = serverPlayers.find { it.id == playerId } ?: return
        if (player.isEliminated) return
        _errorMessage.value = null

        lifeDeltas[playerId] = (lifeDeltas[playerId] ?: 0) + amount
        applyOptimisticDeltas()

        debounceJobs[playerId]?.cancel()
        debounceJobs[playerId] = viewModelScope.launch {
            delay(500)
            flushLifeDelta(playerId)
        }
    }

    private suspend fun flushLifeDelta(playerId: String) {
        val delta = lifeDeltas[playerId] ?: return
        if (delta == 0) return

        lifeDeltas[playerId] = 0
        try {
            cloudFunctionsRepository.adjustLife(gameId, playerId, delta)
        } catch (e: Exception) {
            lifeDeltas[playerId] = (lifeDeltas[playerId] ?: 0) + delta
            applyOptimisticDeltas()
            _errorMessage.value = e.localizedMessage
        }
    }

    fun unveilCurrentPlayer() {
        val player = currentPlayer ?: return
        if (player.isUnveiled || _isPending.value) return
        _errorMessage.value = null
        _isPending.value = true

        viewModelScope.launch {
            try {
                cloudFunctionsRepository.unveilPlayer(gameId)
                AnalyticsService.trackEvent("unveil_identity")
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isPending.value = false
        }
    }

    fun eliminateAndLeave() {
        if (currentPlayer == null || _isPending.value) return
        _errorMessage.value = null
        _isPending.value = true

        viewModelScope.launch {
            try {
                cloudFunctionsRepository.eliminatePlayer(gameId)
                AnalyticsService.trackEvent("forfeit_game")
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isPending.value = false
        }
    }

    fun rollDie() {
        if (_isRollingDie.value) return
        _errorMessage.value = null
        _isRollingDie.value = true
        _dieRollResult.value = null

        viewModelScope.launch {
            try {
                val result = cloudFunctionsRepository.rollPlanarDie(gameId)
                _dieRollResult.value = result
                AnalyticsService.trackEvent("roll_planar_die", mapOf("result" to result))
                // Auto-clear after 3 seconds
                delay(3000)
                _dieRollResult.value = null
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isRollingDie.value = false
        }
    }

    fun resolvePhenomenon() {
        if (_isPending.value) return
        _errorMessage.value = null
        _isPending.value = true

        viewModelScope.launch {
            try {
                val result = cloudFunctionsRepository.resolvePhenomenon(gameId)
                val type = result["type"] as? String
                if (type == "choose") {
                    @Suppress("UNCHECKED_CAST")
                    val options = result["options"] as? List<Map<String, Any?>>
                    _tunnelOptions.value = options?.mapNotNull { dict ->
                        val id = dict["id"] as? String ?: return@mapNotNull null
                        planeDatabase.plane(id)
                    }
                }
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isPending.value = false
        }
    }

    fun selectTunnelPlane(plane: PlaneCard) {
        if (_isPending.value) return
        _errorMessage.value = null
        _isPending.value = true
        _tunnelOptions.value = null

        viewModelScope.launch {
            try {
                cloudFunctionsRepository.selectPlane(gameId, plane.id)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isPending.value = false
        }
    }

    fun endGame(winnerUserIds: List<String>? = null) {
        if (_isPending.value) return
        _errorMessage.value = null
        _isPending.value = true

        viewModelScope.launch {
            try {
                cloudFunctionsRepository.endGame(gameId, winnerUserIds)
                AnalyticsService.trackEvent("end_game")
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isPending.value = false
        }
    }

    fun identityCard(player: Player): IdentityCard? {
        val cardId = player.identityCardId ?: return null
        return cardDatabase.card(cardId)
    }

    fun canSeeRole(player: Player): Boolean {
        if (player.userId == currentUserId) return true
        if (player.isUnveiled) return true
        if (player.role == Role.LEADER) return true
        return false
    }
}
