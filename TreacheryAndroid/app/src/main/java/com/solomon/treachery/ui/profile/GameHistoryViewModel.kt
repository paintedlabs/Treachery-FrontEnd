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

@HiltViewModel
class GameHistoryViewModel @Inject constructor(
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _games = MutableStateFlow<List<Game>>(emptyList())
    val games: StateFlow<List<Game>> = _games.asStateFlow()

    private val _gamePlayers = MutableStateFlow<Map<String, List<Player>>>(emptyMap())
    val gamePlayers: StateFlow<Map<String, List<Player>>> = _gamePlayers.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun loadHistory(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val loadedGames = firestoreRepository.getFinishedGames(userId)
                _games.value = loadedGames

                val playersMap = mutableMapOf<String, List<Player>>()
                for (game in loadedGames) {
                    try {
                        playersMap[game.id] = firestoreRepository.getPlayers(game.id)
                    } catch (_: Exception) { }
                }
                _gamePlayers.value = playersMap
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
            _isLoading.value = false
        }
    }
}
