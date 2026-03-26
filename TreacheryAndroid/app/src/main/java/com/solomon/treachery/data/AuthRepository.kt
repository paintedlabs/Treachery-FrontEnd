package com.solomon.treachery.data

import com.google.firebase.auth.FirebaseUser
import kotlinx.coroutines.flow.Flow

interface AuthRepository {
    val currentUser: FirebaseUser?
    fun authStateFlow(): Flow<FirebaseUser?>
    suspend fun signInAnonymously(): FirebaseUser
    suspend fun signIn(email: String, password: String): FirebaseUser
    suspend fun signUp(email: String, password: String): FirebaseUser
    suspend fun resetPassword(email: String)
    fun signOut()
}
