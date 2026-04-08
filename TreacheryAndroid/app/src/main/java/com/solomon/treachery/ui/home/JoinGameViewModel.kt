package com.solomon.treachery.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.data.CloudFunctionsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class JoinGameViewModel @Inject constructor(
    private val cloudFunctionsRepository: CloudFunctionsRepository
) : ViewModel() {

    private val _isJoining = MutableStateFlow(false)
    val isJoining: StateFlow<Boolean> = _isJoining.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    fun joinGame(
        gameCode: String,
        onSuccess: (gameId: String, isHost: Boolean) -> Unit
    ) {
        _isJoining.value = true
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val result = cloudFunctionsRepository.joinGame(gameCode)
                val gameId = result["gameId"] as? String ?: ""
                val action = result["action"] as? String ?: "joined"

                AnalyticsService.trackEvent(if (action == "already_joined") "rejoin_game" else "join_game")
                onSuccess(gameId, false)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "Failed to join game"
            }
            _isJoining.value = false
        }
    }
}
