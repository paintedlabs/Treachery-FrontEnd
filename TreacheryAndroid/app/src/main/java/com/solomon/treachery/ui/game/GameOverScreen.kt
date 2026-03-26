package com.solomon.treachery.ui.game

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*

@Composable
fun GameOverScreen(
    currentUserId: String?,
    onNavigateHome: () -> Unit,
    viewModel: GameBoardViewModel = hiltViewModel()
) {
    val game by viewModel.game.collectAsState()
    val players by viewModel.players.collectAsState()

    var animateIn by remember { mutableStateOf(false) }
    val trophyScale by animateFloatAsState(
        targetValue = if (animateIn) 1f else 0.3f,
        animationSpec = spring(dampingRatio = 0.6f, stiffness = 200f),
        label = "trophy"
    )

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("GameOver")
        viewModel.currentUserId = currentUserId
        animateIn = true
    }

    val isTreacheryMode = game?.gameMode?.includesTreachery ?: true
    val winningTeam = viewModel.winningTeam
    val winColor = winningTeam?.roleColor ?: MtgGold

    Box(modifier = Modifier.fillMaxSize()) {
        // Background with winning team color glow
        MtgRadialBackground()
        Box(
            Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(winColor.copy(alpha = 0.15f), MtgBackground),
                    radius = 420f
                )
            )
        )

        if (players.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MtgGold)
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(Modifier.weight(1f))

                if (isTreacheryMode && winningTeam != null) {
                    // Trophy
                    Icon(
                        Icons.Default.EmojiEvents,
                        contentDescription = "Trophy",
                        tint = winColor,
                        modifier = Modifier.size(56.dp).scale(trophyScale)
                    )
                    Spacer(Modifier.height(16.dp))
                    Text("Game Over", fontSize = 40.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary)
                    OrnateDivider(modifier = Modifier.padding(horizontal = 40.dp, vertical = 8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.size(16.dp).clip(CircleShape).background(winColor))
                        Text("${winningTeam.displayName} Wins!", fontSize = 24.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = winColor)
                    }
                } else {
                    // Non-treachery
                    Icon(
                        Icons.Default.Flag,
                        contentDescription = null,
                        tint = MtgGold,
                        modifier = Modifier.size(56.dp).scale(trophyScale)
                    )
                    Spacer(Modifier.height(12.dp))
                    Text("Game Over", fontSize = 36.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary)
                    OrnateDivider(modifier = Modifier.padding(horizontal = 40.dp, vertical = 8.dp))
                    game?.gameMode?.let { mode ->
                        Text(mode.displayName, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MtgBackground,
                            modifier = Modifier.background(MtgGold, RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 4.dp))
                    }
                }

                Spacer(Modifier.height(24.dp))

                // Player list
                MtgCardFrame(modifier = Modifier.fillMaxWidth()) {
                    Column {
                        players.forEachIndexed { index, player ->
                            Row(
                                modifier = Modifier.padding(vertical = 10.dp, horizontal = 16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                player.playerColor?.let { hex ->
                                    val color = try { androidx.compose.ui.graphics.Color(android.graphics.Color.parseColor(hex)) } catch (_: Exception) { MtgTextSecondary }
                                    Box(Modifier.width(3.dp).height(32.dp).clip(RoundedCornerShape(2.dp)).background(color))
                                    Spacer(Modifier.width(8.dp))
                                }

                                if (isTreacheryMode) {
                                    Box(Modifier.size(12.dp).clip(CircleShape).background(player.role?.roleColor ?: MtgTextSecondary))
                                    Spacer(Modifier.width(8.dp))
                                }

                                Column(modifier = Modifier.weight(1f)) {
                                    Text(player.displayName, fontWeight = FontWeight.Medium, color = MtgTextPrimary)
                                    if (!player.commanderName.isNullOrEmpty()) {
                                        Text(player.commanderName!!, fontSize = 12.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, color = MtgTextSecondary)
                                    }
                                }

                                if (isTreacheryMode) {
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(player.role?.displayName ?: "Unknown", fontSize = 14.sp, color = player.role?.roleColor ?: MtgTextSecondary)
                                        viewModel.identityCard(player)?.let { card ->
                                            Text(card.name, fontSize = 12.sp, color = MtgTextSecondary)
                                        }
                                    }
                                }

                                if (player.isEliminated) {
                                    Spacer(Modifier.width(4.dp))
                                    Icon(Icons.Default.Cancel, null, tint = MtgError, modifier = Modifier.size(14.dp))
                                }
                            }

                            if (index < players.lastIndex) {
                                HorizontalDivider(color = MtgDivider, modifier = Modifier.padding(horizontal = 16.dp))
                            }
                        }
                    }
                }

                Spacer(Modifier.weight(1f))

                MtgPrimaryButton(
                    text = "Return to Home",
                    onClick = onNavigateHome,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            }
        }
    }
}
