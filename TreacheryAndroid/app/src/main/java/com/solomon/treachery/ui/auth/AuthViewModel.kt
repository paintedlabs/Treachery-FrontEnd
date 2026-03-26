package com.solomon.treachery.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseUser
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.data.AuthRepository
import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.model.TreacheryUser
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val firestoreRepository: FirestoreRepository
) : ViewModel() {

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    val currentUserId: String?
        get() = (authState.value as? AuthState.Authenticated)?.user?.uid

    init {
        viewModelScope.launch {
            authRepository.authStateFlow().collect { user ->
                if (user != null) {
                    _authState.value = AuthState.Authenticated(user)
                    AnalyticsService.setUserId(user.uid)
                    AnalyticsService.setUserProperties(
                        mapOf("auth_method" to if (user.isAnonymous) "guest" else "email")
                    )
                    createUserDocumentIfNeeded(user)
                } else {
                    _authState.value = AuthState.Unauthenticated
                    AnalyticsService.setUserId(null)
                }
            }
        }
    }

    fun signIn(email: String, password: String) {
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                authRepository.signIn(email, password)
                AnalyticsService.trackEvent("sign_in", mapOf("method" to "email"))
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun signUp(email: String, password: String) {
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                authRepository.signUp(email, password)
                AnalyticsService.trackEvent("sign_up", mapOf("method" to "email"))
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun signInAsGuest() {
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                authRepository.signInAnonymously()
                AnalyticsService.trackEvent("sign_in", mapOf("method" to "guest"))
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun resetPassword(email: String) {
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                authRepository.resetPassword(email)
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage
            }
        }
    }

    fun signOut() {
        _errorMessage.value = null
        try {
            authRepository.signOut()
            AnalyticsService.trackEvent("sign_out")
        } catch (e: Exception) {
            _errorMessage.value = e.localizedMessage
        }
    }

    fun clearError() {
        _errorMessage.value = null
    }

    private suspend fun createUserDocumentIfNeeded(user: FirebaseUser) {
        try {
            val existingUser = firestoreRepository.getUser(user.uid)
            if (existingUser == null) {
                val displayName = user.displayName ?: user.email ?: "Guest"
                val newUser = TreacheryUser(
                    id = user.uid,
                    displayName = displayName,
                    email = user.email,
                    phoneNumber = user.phoneNumber,
                    friendIds = emptyList(),
                    createdAt = Timestamp.now()
                )
                firestoreRepository.createUser(newUser)
            }
        } catch (e: Exception) {
            // Non-fatal: user document creation failure shouldn't block auth
        }
    }
}
