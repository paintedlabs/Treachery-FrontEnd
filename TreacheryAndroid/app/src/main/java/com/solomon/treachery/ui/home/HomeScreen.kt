package com.solomon.treachery.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.model.Game
import com.solomon.treachery.model.GameState
import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.ui.auth.AuthViewModel
import com.solomon.treachery.ui.theme.*

@Composable
fun HomeScreen(
    authViewModel: AuthViewModel,
    onNavigateToCreateGame: () -> Unit,
    onNavigateToJoinGame: () -> Unit,
    onNavigateToProfile: () -> Unit,
    onNavigateToFriends: () -> Unit,
    onNavigateToHistory: () -> Unit,
    onNavigateToLobby: (gameId: String, isHost: Boolean) -> Unit,
    onNavigateToGameBoard: (gameId: String) -> Unit
) {
    var activeGame by remember { mutableStateOf<Game?>(null) }

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("Home")
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MtgRadialBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Title
            MtgGoldShimmerText("Treachery")
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "A Game of Hidden Allegiance",
                style = MaterialTheme.typography.bodySmall,
                color = MtgTextSecondary.copy(alpha = 0.8f),
                textAlign = TextAlign.Center
            )
            OrnateDivider(modifier = Modifier.padding(horizontal = 40.dp, vertical = 4.dp))

            Spacer(modifier = Modifier.height(40.dp))

            // Active game banner
            activeGame?.let { game ->
                MtgCardFrame(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                if (game.state == GameState.IN_PROGRESS) {
                                    onNavigateToGameBoard(game.id)
                                } else {
                                    val isHost = game.hostId == authViewModel.currentUserId
                                    onNavigateToLobby(game.id, isHost)
                                }
                            }
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(MtgGold.copy(alpha = 0.15f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Default.SportsEsports,
                                contentDescription = null,
                                tint = MtgGoldBright
                            )
                        }

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                if (game.state == GameState.IN_PROGRESS) "Game in Progress" else "Game Waiting",
                                style = MaterialTheme.typography.titleMedium,
                                color = MtgGoldBright
                            )
                            Text(
                                "Tap to rejoin",
                                style = MaterialTheme.typography.bodySmall,
                                color = MtgTextSecondary
                            )
                        }

                        Icon(
                            Icons.Default.ChevronRight,
                            contentDescription = null,
                            tint = MtgGold
                        )
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Main action buttons
            MtgPrimaryButton(
                text = "Create Game",
                onClick = onNavigateToCreateGame
            )
            Spacer(modifier = Modifier.height(12.dp))
            MtgSecondaryButton(
                text = "Join Game",
                onClick = onNavigateToJoinGame
            )

            Spacer(modifier = Modifier.weight(1f))

            // Bottom nav tabs
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        MtgSurface.copy(alpha = 0.85f),
                        RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)
                    )
                    .padding(vertical = 12.dp, horizontal = 24.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                BottomNavItem(Icons.Default.Schedule, "History", onClick = onNavigateToHistory)
                BottomNavItem(Icons.Default.Group, "Friends", onClick = onNavigateToFriends)
                BottomNavItem(Icons.Default.AccountCircle, "Profile", onClick = onNavigateToProfile)
            }
        }
    }
}

@Composable
private fun BottomNavItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier.clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(icon, contentDescription = label, tint = MtgTextSecondary, modifier = Modifier.size(24.dp))
        Text(label, style = MaterialTheme.typography.bodySmall, color = MtgTextSecondary, fontSize = 12.sp)
    }
}
