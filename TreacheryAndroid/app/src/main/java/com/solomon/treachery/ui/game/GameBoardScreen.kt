package com.solomon.treachery.ui.game

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*
import com.solomon.treachery.ui.util.PlayerColors

@Composable
fun GameBoardScreen(
    currentUserId: String?,
    onNavigateToGameOver: (gameId: String) -> Unit,
    onNavigateHome: () -> Unit,
    viewModel: GameBoardViewModel = hiltViewModel()
) {
    val game by viewModel.game.collectAsState()
    val players by viewModel.players.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val isGameUnavailable by viewModel.isGameUnavailable.collectAsState()
    val isPending by viewModel.isPending.collectAsState()

    var showForfeitDialog by remember { mutableStateOf(false) }
    var showUnveilDialog by remember { mutableStateOf(false) }
    var showEndGameConfirm by remember { mutableStateOf(false) }
    var showCardDetail by remember { mutableStateOf(false) }
    var showColorPicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("GameBoard")
        viewModel.currentUserId = currentUserId
    }

    // Navigate to game over when finished
    LaunchedEffect(game?.state) {
        if (game?.state == GameState.FINISHED) {
            onNavigateToGameOver(viewModel.gameId)
        }
    }

    // Forfeit dialog
    if (showForfeitDialog) {
        AlertDialog(
            onDismissRequest = { showForfeitDialog = false },
            title = { Text("Forfeit Game?", color = MtgTextPrimary) },
            text = { Text("You will be eliminated from the game. This cannot be undone.", color = MtgTextSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    showForfeitDialog = false
                    viewModel.eliminateAndLeave()
                    onNavigateToGameOver(viewModel.gameId)
                }) { Text("Forfeit", color = MtgError) }
            },
            dismissButton = {
                TextButton(onClick = { showForfeitDialog = false }) { Text("Cancel", color = MtgGold) }
            },
            containerColor = MtgSurface
        )
    }

    // Unveil dialog
    if (showUnveilDialog) {
        val card = viewModel.currentIdentityCard()
        val player = viewModel.currentPlayer
        AlertDialog(
            onDismissRequest = { showUnveilDialog = false },
            title = { Text("Unveil your identity?", color = MtgTextPrimary) },
            text = {
                Text(
                    "This will reveal your role (${player?.role?.displayName ?: ""}) and card (${card?.name ?: ""}) to all players. This cannot be undone.",
                    color = MtgTextSecondary
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showUnveilDialog = false
                    viewModel.unveilCurrentPlayer()
                }) { Text("Unveil", color = MtgGold) }
            },
            dismissButton = {
                TextButton(onClick = { showUnveilDialog = false }) { Text("Cancel", color = MtgTextSecondary) }
            },
            containerColor = MtgSurface
        )
    }

    // End game confirm
    if (showEndGameConfirm) {
        AlertDialog(
            onDismissRequest = { showEndGameConfirm = false },
            title = { Text("End Game?", color = MtgTextPrimary) },
            text = { Text("This will end the game for all players.", color = MtgTextSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    showEndGameConfirm = false
                    viewModel.endGame()
                }) { Text("End Game", color = MtgError) }
            },
            dismissButton = {
                TextButton(onClick = { showEndGameConfirm = false }) { Text("Cancel", color = MtgGold) }
            },
            containerColor = MtgSurface
        )
    }

    // Card detail bottom sheet
    if (showCardDetail) {
        val card = viewModel.currentIdentityCard()
        val player = viewModel.currentPlayer
        if (card != null && player != null) {
            IdentityCardSheet(card = card, player = player, onDismiss = { showCardDetail = false })
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Background with optional player color tint
        MtgRadialBackground()
        viewModel.currentPlayer?.playerColor?.let { hex ->
            val tintColor = remember(hex) {
                try { Color(android.graphics.Color.parseColor(hex)).copy(alpha = 0.15f) }
                catch (_: Exception) { Color.Transparent }
            }
            Box(Modifier.fillMaxSize().background(tintColor))
        }

        when {
            isGameUnavailable -> {
                Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Icon(Icons.Default.WifiOff, null, tint = MtgGold, modifier = Modifier.size(48.dp))
                    Spacer(Modifier.height(12.dp))
                    Text("Game Unavailable", style = MaterialTheme.typography.headlineMedium, color = MtgTextPrimary)
                    Spacer(Modifier.height(8.dp))
                    Text("This game is no longer available.", color = MtgTextSecondary, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(24.dp))
                    MtgPrimaryButton("Return to Home", onClick = onNavigateHome, modifier = Modifier.padding(horizontal = 40.dp))
                }
            }
            players.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = MtgGold)
                        Spacer(Modifier.height(12.dp))
                        Text("Loading game...", color = MtgTextSecondary)
                    }
                }
            }
            else -> {
                Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
                    // Identity card header (treachery only)
                    if (viewModel.isTreacheryActive) {
                        val card = viewModel.currentIdentityCard()
                        val player = viewModel.currentPlayer
                        if (card != null && player != null) {
                            IdentityCardHeader(
                                card = card,
                                player = player,
                                onClick = { showCardDetail = true }
                            )
                        }
                    }

                    // Planechase section (when active and not own-deck mode)
                    if (viewModel.isPlanechaseActive && !viewModel.isOwnDeckMode) {
                        if (viewModel.isChaoticAetherActive) {
                            ChaoticAetherIndicator()
                        }
                        viewModel.currentPlane?.let { plane ->
                            var showPlaneDetail by remember { mutableStateOf(false) }
                            PlaneCardBanner(
                                plane = plane,
                                secondaryPlane = viewModel.secondaryPlane,
                                onClick = { showPlaneDetail = true }
                            )
                            if (showPlaneDetail) {
                                PlaneCardDetailSheet(plane = plane, onDismiss = { showPlaneDetail = false })
                            }
                            if (plane.isPhenomenon) {
                                PhenomenonOverlay(
                                    plane = plane,
                                    isPending = isPending,
                                    onResolve = { viewModel.resolvePhenomenon() }
                                )
                            }
                        }
                    }

                    OrnateDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))

                    // Player list
                    Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        MtgSectionHeader("Players", modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

                        MtgCardFrame(modifier = Modifier.padding(horizontal = 16.dp)) {
                            Column {
                                players.forEachIndexed { index, player ->
                                    GamePlayerRow(
                                        player = player,
                                        isCurrentUser = player.userId == currentUserId,
                                        isTreacheryActive = viewModel.isTreacheryActive,
                                        canSeeRole = viewModel.canSeeRole(player),
                                        onAdjustLife = { amount -> viewModel.adjustLife(player.id, amount) }
                                    )
                                    if (index < players.lastIndex) {
                                        HorizontalDivider(color = MtgDivider, modifier = Modifier.padding(horizontal = 16.dp))
                                    }
                                }
                            }
                        }
                    }

                    // Error
                    errorMessage?.let {
                        MtgErrorBanner(it, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                    }

                    // Eliminated spectator banner
                    if (viewModel.isTreacheryActive && viewModel.currentPlayer?.isEliminated == true) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MtgError.copy(alpha = 0.1f))
                                .padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text("You've Been Eliminated", color = MtgError, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif)
                            Spacer(Modifier.height(4.dp))
                            Text("You're now spectating.", color = MtgTextSecondary, fontSize = 12.sp, fontStyle = FontStyle.Italic)
                        }
                    }

                    // Planar die bar (when planechase active)
                    if (viewModel.isPlanechaseActive) {
                        val dieResult by viewModel.dieRollResult.collectAsState()
                        val isRolling by viewModel.isRollingDie.collectAsState()
                        val tunnelOpts by viewModel.tunnelOptions.collectAsState()

                        PlanarDieBar(
                            dieRollResult = dieResult,
                            isRollingDie = isRolling,
                            dieRollCost = viewModel.dieRollCost,
                            lastDieRollerName = viewModel.lastDieRollerName,
                            isPending = isPending,
                            onRollDie = { viewModel.rollDie() }
                        )

                        // Interplanar Tunnel picker
                        tunnelOpts?.let { options ->
                            InterplanarTunnelPicker(
                                options = options,
                                isPending = isPending,
                                onSelectPlane = { viewModel.selectTunnelPlane(it) },
                                onDismiss = { }
                            )
                        }
                    }

                    // Unveil button (treachery, not eliminated, not unveiled, not leader)
                    val cp = viewModel.currentPlayer
                    if (viewModel.isTreacheryActive && cp != null && !cp.isEliminated && !cp.isUnveiled && cp.role != Role.LEADER) {
                        MtgPrimaryButton(
                            text = "Unveil Identity",
                            onClick = { showUnveilDialog = true },
                            enabled = !isPending,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }

                    // End game button (non-treachery, host only)
                    if (!viewModel.isTreacheryActive && viewModel.isHost) {
                        MtgSecondaryButton(
                            text = "End Game",
                            onClick = { showEndGameConfirm = true },
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }

                    // Forfeit button (treachery, not eliminated)
                    if (viewModel.isTreacheryActive && cp != null && !cp.isEliminated) {
                        TextButton(
                            onClick = { showForfeitDialog = true },
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
                        ) {
                            Icon(Icons.Default.Flag, null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Forfeit", color = MtgTextSecondary, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun IdentityCardHeader(card: IdentityCard, player: Player, onClick: () -> Unit) {
    val isVisible = player.isUnveiled || player.role == Role.LEADER
    val roleColor = player.role?.roleColor ?: MtgGold

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(
                if (isVisible) Brush.linearGradient(listOf(roleColor.copy(alpha = 0.1f), Color.Transparent))
                else Brush.linearGradient(listOf(MtgSurface, MtgSurface))
            )
            .padding(16.dp)
    ) {
        if (isVisible) {
            // Revealed header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(12.dp).clip(CircleShape).background(roleColor))
                    Text(player.role?.displayName ?: "", fontWeight = FontWeight.Bold, color = roleColor)
                }
                Spacer(Modifier.weight(1f))
                Icon(Icons.Default.Favorite, null, tint = MtgError, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text("${player.lifeTotal}", fontSize = 28.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary)
            }
            Spacer(Modifier.height(4.dp))
            Row {
                Text(card.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary)
                Spacer(Modifier.weight(1f))
                Icon(Icons.Default.ChevronRight, null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
            }
            Text(card.abilityText, fontSize = 12.sp, color = MtgTextSecondary, maxLines = 3)
            Spacer(Modifier.height(4.dp))
            Row {
                if (player.isUnveiled) {
                    Text("UNVEILED", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = MtgBackground,
                        modifier = Modifier.background(roleColor, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
                } else if (player.role == Role.LEADER) {
                    Text("LEADER — ALWAYS VISIBLE", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = MtgGold,
                        modifier = Modifier.background(MtgGold.copy(alpha = 0.15f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
                }
                Spacer(Modifier.weight(1f))
                Text("Tap for details", fontSize = 10.sp, color = MtgTextSecondary)
            }
        } else {
            // Concealed header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.VisibilityOff, null, tint = MtgGold)
                Spacer(Modifier.weight(1f))
                Icon(Icons.Default.Favorite, null, tint = MtgError, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text("${player.lifeTotal}", fontSize = 28.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary)
            }
            Text("Tap to peek at your identity", color = MtgTextSecondary, fontSize = 14.sp)
        }
    }
}

@Composable
private fun GamePlayerRow(
    player: Player,
    isCurrentUser: Boolean,
    isTreacheryActive: Boolean,
    canSeeRole: Boolean,
    onAdjustLife: (Int) -> Unit
) {
    Row(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Color bar
        player.playerColor?.let { hex ->
            val color = try { Color(android.graphics.Color.parseColor(hex)) } catch (_: Exception) { MtgTextSecondary }
            Box(Modifier.width(3.dp).height(40.dp).clip(RoundedCornerShape(2.dp)).background(color))
            Spacer(Modifier.width(8.dp))
        }

        // Player info
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    player.displayName,
                    fontWeight = if (isCurrentUser) FontWeight.Bold else FontWeight.Normal,
                    color = if (player.isEliminated) MtgTextSecondary else MtgTextPrimary,
                    textDecoration = if (player.isEliminated) TextDecoration.LineThrough else null
                )
                if (isCurrentUser) {
                    Text("You", fontSize = 10.sp, color = MtgGold,
                        modifier = Modifier.background(MtgGold.copy(alpha = 0.15f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 1.dp))
                }
                if (player.isEliminated) {
                    Icon(Icons.Default.Cancel, null, tint = MtgError, modifier = Modifier.size(14.dp))
                }
            }
            if (!player.commanderName.isNullOrEmpty()) {
                Text(player.commanderName!!, fontSize = 12.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, color = MtgTextSecondary)
            }
            if (canSeeRole && player.role != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(player.role!!.roleColor))
                    Text(player.role!!.displayName, fontSize = 12.sp, color = player.role!!.roleColor)
                    if (player.isUnveiled && player.role != Role.LEADER) {
                        Text("(Unveiled)", fontSize = 10.sp, color = MtgTextSecondary)
                    }
                }
            } else if (isTreacheryActive) {
                Text("Role Hidden", fontSize = 12.sp, color = MtgTextSecondary)
            }
        }

        // Life controls
        if (!player.isEliminated) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(onClick = { onAdjustLife(-1) }, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.Default.RemoveCircle, "Decrease life", tint = MtgAssassin, modifier = Modifier.size(32.dp))
                }
                Text("${player.lifeTotal}", fontSize = 32.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary,
                    modifier = Modifier.widthIn(min = 48.dp), textAlign = TextAlign.Center)
                IconButton(onClick = { onAdjustLife(1) }, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.Default.AddCircle, "Increase life", tint = MtgSuccess, modifier = Modifier.size(32.dp))
                }
            }
        } else {
            Text("Eliminated", fontSize = 12.sp, color = MtgError)
        }
    }
}
