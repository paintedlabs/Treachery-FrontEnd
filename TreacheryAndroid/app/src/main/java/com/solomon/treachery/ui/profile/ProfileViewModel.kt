package com.solomon.treachery.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.model.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class GameStats(
    val totalGames: Int = 0,
    val wins: Int = 0,
    val losses: Int = 0,
    val roleBreakdown: Map<Role, Int> = emptyMap()
) {
    val winRateText: String
        get() = if (totalGames > 0) "${(wins.toDouble() / totalGames * 100).toInt()}%" else "--"
}

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _user = MutableStateFlow<TreacheryUser?>(null)
    val user: StateFlow<TreacheryUser?> = _user.asStateFlow()

    private val _gameStats = MutableStateFlow<GameStats?>(null)
    val gameStats: StateFlow<GameStats?> = _gameStats.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()

    fun loadData(userId: String) {
        viewModelScope.launch {
            _errorMessage.value = null
            try {
                _user.value = firestoreRepository.getUser(userId)
                val games = firestoreRepository.getFinishedGames(userId)
                calculateStats(games, userId)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    private suspend fun calculateStats(games: List<Game>, userId: String) {
        var wins = 0
        var losses = 0
        val roleBreakdown = mutableMapOf<Role, Int>()

        for (game in games) {
            try {
                val players = firestoreRepository.getPlayers(game.id)
                val myPlayer = players.find { it.userId == userId }
                val myRole = myPlayer?.role ?: continue

                roleBreakdown[myRole] = (roleBreakdown[myRole] ?: 0) + 1

                val winTeamString = game.winningTeam ?: continue
                val winRole = Role.fromValue(winTeamString) ?: continue
                val didWin = if (winRole == Role.LEADER) {
                    myRole == Role.LEADER || myRole == Role.GUARDIAN
                } else {
                    myRole == winRole
                }
                if (didWin) wins++ else losses++
            } catch (_: Exception) { }
        }

        _gameStats.value = GameStats(
            totalGames = games.size,
            wins = wins,
            losses = losses,
            roleBreakdown = roleBreakdown
        )
    }

    fun saveName(newName: String) {
        val currentUser = _user.value ?: return
        if (newName.isBlank()) return
        _isSaving.value = true
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val updated = currentUser.copy(displayName = newName.trim())
                firestoreRepository.updateUser(updated)
                _user.value = updated
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isSaving.value = false
        }
    }
}
