package com.solomon.treachery.ui.navigation

object Routes {
    const val LOGIN = "login"
    const val SIGN_UP = "sign_up"
    const val FORGOT_PASSWORD = "forgot_password"
    const val PHONE_AUTH = "phone_auth"
    const val DISPLAY_NAME_PROMPT = "onboarding_name"
    const val WELCOME = "onboarding_welcome"
    const val HOME = "home"
    const val CREATE_GAME = "create_game"
    const val JOIN_GAME = "join_game"
    const val LOBBY = "lobby/{gameId}/{isHost}"
    const val GAME_BOARD = "game/{gameId}"
    const val GAME_OVER = "game_over/{gameId}"
    const val PROFILE = "profile"
    const val FRIENDS = "friends"
    const val GAME_HISTORY = "history"

    fun lobby(gameId: String, isHost: Boolean) = "lobby/$gameId/$isHost"
    fun gameBoard(gameId: String) = "game/$gameId"
    fun gameOver(gameId: String) = "game_over/$gameId"
}
