package com.solomon.treachery.ui.navigation

import androidx.compose.runtime.*
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.solomon.treachery.ui.auth.*
import com.solomon.treachery.ui.game.GameBoardScreen
import com.solomon.treachery.ui.game.GameOverScreen
import com.solomon.treachery.ui.home.CreateGameScreen
import com.solomon.treachery.ui.home.HomeScreen
import com.solomon.treachery.ui.home.JoinGameScreen
import com.solomon.treachery.ui.lobby.LobbyScreen

@Composable
fun TreacheryNavHost() {
    val navController = rememberNavController()
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.authState.collectAsState()

    LaunchedEffect(authState) {
        when (authState) {
            is AuthState.Authenticated -> {
                navController.navigate(Routes.HOME) {
                    popUpTo(0) { inclusive = true }
                }
            }
            is AuthState.Unauthenticated -> {
                navController.navigate(Routes.LOGIN) {
                    popUpTo(0) { inclusive = true }
                }
            }
            is AuthState.Loading -> { /* wait */ }
        }
    }

    NavHost(
        navController = navController,
        startDestination = Routes.LOGIN
    ) {
        // Auth screens
        composable(Routes.LOGIN) {
            LoginScreen(
                authViewModel = authViewModel,
                onNavigateToSignUp = { navController.navigate(Routes.SIGN_UP) },
                onNavigateToForgotPassword = { navController.navigate(Routes.FORGOT_PASSWORD) }
            )
        }

        composable(Routes.SIGN_UP) {
            SignUpScreen(
                authViewModel = authViewModel,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(Routes.FORGOT_PASSWORD) {
            ForgotPasswordScreen(
                authViewModel = authViewModel,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(Routes.PHONE_AUTH) {
            PhoneAuthScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Main app screens
        composable(Routes.HOME) {
            HomeScreen(
                authViewModel = authViewModel,
                onNavigateToCreateGame = { navController.navigate(Routes.CREATE_GAME) },
                onNavigateToJoinGame = { navController.navigate(Routes.JOIN_GAME) },
                onNavigateToProfile = { navController.navigate(Routes.PROFILE) },
                onNavigateToFriends = { navController.navigate(Routes.FRIENDS) },
                onNavigateToHistory = { navController.navigate(Routes.GAME_HISTORY) },
                onNavigateToLobby = { gameId, isHost ->
                    navController.navigate(Routes.lobby(gameId, isHost))
                },
                onNavigateToGameBoard = { gameId ->
                    navController.navigate(Routes.gameBoard(gameId))
                }
            )
        }

        composable(Routes.CREATE_GAME) {
            CreateGameScreen(
                currentUserId = authViewModel.currentUserId,
                onNavigateBack = { navController.popBackStack() },
                onNavigateToLobby = { gameId, isHost ->
                    navController.navigate(Routes.lobby(gameId, isHost)) {
                        popUpTo(Routes.HOME)
                    }
                }
            )
        }

        composable(Routes.JOIN_GAME) {
            JoinGameScreen(
                currentUserId = authViewModel.currentUserId,
                onNavigateBack = { navController.popBackStack() },
                onNavigateToLobby = { gameId, isHost ->
                    navController.navigate(Routes.lobby(gameId, isHost)) {
                        popUpTo(Routes.HOME)
                    }
                }
            )
        }

        composable(
            route = Routes.LOBBY,
            arguments = listOf(
                navArgument("gameId") { type = NavType.StringType },
                navArgument("isHost") { type = NavType.BoolType }
            )
        ) {
            LobbyScreen(
                currentUserId = authViewModel.currentUserId,
                onNavigateToGameBoard = { gameId ->
                    navController.navigate(Routes.gameBoard(gameId)) {
                        popUpTo(Routes.HOME)
                    }
                },
                onNavigateHome = {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                }
            )
        }

        composable(
            route = Routes.GAME_BOARD,
            arguments = listOf(navArgument("gameId") { type = NavType.StringType })
        ) {
            GameBoardScreen(
                currentUserId = authViewModel.currentUserId,
                onNavigateToGameOver = { gameId ->
                    navController.navigate(Routes.gameOver(gameId)) {
                        popUpTo(Routes.HOME)
                    }
                },
                onNavigateHome = {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                }
            )
        }

        composable(
            route = Routes.GAME_OVER,
            arguments = listOf(navArgument("gameId") { type = NavType.StringType })
        ) {
            GameOverScreen(
                currentUserId = authViewModel.currentUserId,
                onNavigateHome = {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                }
            )
        }

        composable(Routes.PROFILE) {
            PlaceholderScreen("Profile", onBack = { navController.popBackStack() })
        }

        composable(Routes.FRIENDS) {
            PlaceholderScreen("Friends", onBack = { navController.popBackStack() })
        }

        composable(Routes.GAME_HISTORY) {
            PlaceholderScreen("Game History", onBack = { navController.popBackStack() })
        }
    }
}
