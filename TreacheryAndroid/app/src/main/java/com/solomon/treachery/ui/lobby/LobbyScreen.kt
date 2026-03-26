package com.solomon.treachery.ui.lobby

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.ui.theme.*
import com.solomon.treachery.ui.util.PlayerColors
import com.solomon.treachery.model.GameState
import com.solomon.treachery.model.Player
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun LobbyScreen(
    currentUserId: String?,
    onNavigateToGameBoard: (gameId: String) -> Unit,
    onNavigateHome: () -> Unit,
    viewModel: LobbyViewModel = hiltViewModel()
) {
    val game by viewModel.game.collectAsState()
    val players by viewModel.players.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val isStartingGame by viewModel.isStartingGame.collectAsState()
    val isGameDisbanded by viewModel.isGameDisbanded.collectAsState()

    var isLeaving by remember { mutableStateOf(false) }
    var showHostLeftAlert by remember { mutableStateOf(false) }
    var showColorPicker by remember { mutableStateOf(false) }
    var commanderNameInput by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    var debounceJob by remember { mutableStateOf<Job?>(null) }

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("Lobby")
        viewModel.currentUserId = currentUserId
    }

    // Sync commander name from server
    LaunchedEffect(players) {
        if (commanderNameInput.isEmpty()) {
            viewModel.currentPlayer?.commanderName?.let {
                commanderNameInput = it
            }
        }
    }

    // Navigate to game board when game starts
    LaunchedEffect(game?.state) {
        if (game?.state == GameState.IN_PROGRESS) {
            onNavigateToGameBoard(viewModel.gameId)
        }
    }

    // Show alert when host disbands
    LaunchedEffect(isGameDisbanded) {
        if (isGameDisbanded && !viewModel.isHost) {
            showHostLeftAlert = true
        }
    }

    // Host left alert dialog
    if (showHostLeftAlert) {
        AlertDialog(
            onDismissRequest = { },
            title = { Text("Game Disbanded", color = MtgTextPrimary) },
            text = { Text("The host has left and the game was closed.", color = MtgTextSecondary) },
            confirmButton = {
                TextButton(onClick = { onNavigateHome() }) {
                    Text("OK", color = MtgGold)
                }
            },
            containerColor = MtgSurface
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MtgRadialBackground()

        when {
            game == null && errorMessage == null -> {
                // Loading
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MtgGold)
                }
            }
            isGameDisbanded -> {
                // Disbanded
                Column(
                    Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(Icons.Default.Cancel, null, tint = MtgError, modifier = Modifier.size(48.dp))
                    Spacer(Modifier.height(12.dp))
                    Text("Game Disbanded", style = MaterialTheme.typography.headlineMedium, color = MtgTextPrimary)
                    Spacer(Modifier.height(8.dp))
                    Text("The host has left and the game was closed.", color = MtgTextSecondary, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(24.dp))
                    MtgPrimaryButton("Return Home", onClick = onNavigateHome, modifier = Modifier.padding(horizontal = 40.dp))
                }
            }
            else -> {
                // Lobby content
                Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
                    com.solomon.treachery.ui.navigation.ConnectionBanner()

                    // Game code card
                    game?.let { g ->
                        GameCodeCard(
                            code = g.code,
                            gameModeName = g.gameMode.displayName
                        )
                    }

                    OrnateDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))

                    // Player list
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                    ) {
                        MtgSectionHeader(
                            "Players (${players.size})",
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )

                        if (players.isEmpty()) {
                            Text(
                                "Waiting for players to join...",
                                color = MtgTextSecondary,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp),
                                textAlign = TextAlign.Center
                            )
                        } else {
                            MtgCardFrame(modifier = Modifier.padding(horizontal = 16.dp)) {
                                Column {
                                    players.forEachIndexed { index, player ->
                                        val isMe = player.userId == currentUserId
                                        val isPlayerHost = player.userId == game?.hostId

                                        PlayerRow(
                                            player = player,
                                            isMe = isMe,
                                            isHost = isPlayerHost,
                                            showColorPicker = isMe && showColorPicker,
                                            commanderNameInput = if (isMe) commanderNameInput else "",
                                            onToggleColorPicker = { if (isMe) showColorPicker = !showColorPicker },
                                            onColorChange = { hex -> viewModel.updatePlayerColor(hex) },
                                            onCommanderNameChange = { name ->
                                                commanderNameInput = name
                                                debounceJob?.cancel()
                                                debounceJob = scope.launch {
                                                    delay(500)
                                                    viewModel.updateCommanderName(name.ifEmpty { null })
                                                }
                                            }
                                        )

                                        if (index < players.lastIndex) {
                                            HorizontalDivider(color = MtgDivider, modifier = Modifier.padding(horizontal = 16.dp))
                                        }
                                    }
                                }
                            }
                        }

                        if (!viewModel.isHost) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(14.dp),
                                    color = MtgGold,
                                    strokeWidth = 2.dp
                                )
                                Spacer(Modifier.width(8.dp))
                                Text("Waiting for host to start the game...", color = MtgTextSecondary, fontSize = 14.sp)
                            }
                        }
                    }

                    // Error
                    errorMessage?.let {
                        Text(it, color = MtgError, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp))
                    }

                    // Bottom buttons
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (viewModel.isHost) {
                            MtgPrimaryButton(
                                text = if (isStartingGame) "Starting..." else "Start Game",
                                onClick = { viewModel.startGame() },
                                enabled = viewModel.canStartGame && !isStartingGame,
                                isLoading = isStartingGame
                            )
                            if (!viewModel.canStartGame && players.size < viewModel.minimumPlayerCount) {
                                Text(
                                    "Need at least ${viewModel.minimumPlayerCount} players to start",
                                    color = MtgTextSecondary,
                                    fontSize = 12.sp,
                                    modifier = Modifier.fillMaxWidth(),
                                    textAlign = TextAlign.Center
                                )
                            }
                        }

                        TextButton(
                            onClick = {
                                isLeaving = true
                                viewModel.leaveGame()
                                onNavigateHome()
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = !isLeaving
                        ) {
                            if (isLeaving) {
                                CircularProgressIndicator(Modifier.size(14.dp), color = MtgError, strokeWidth = 2.dp)
                                Spacer(Modifier.width(8.dp))
                            }
                            Text(if (isLeaving) "Leaving..." else "Leave Game", color = MtgError)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GameCodeCard(code: String, gameModeName: String) {
    val context = LocalContext.current

    MtgCardFrame(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Column(
            modifier = Modifier.padding(vertical = 24.dp, horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            MtgSectionHeader("Game Code")

            MtgGoldShimmerText(code, fontSize = 52f)

            // Game mode badge
            Text(
                gameModeName,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MtgBackground,
                modifier = Modifier
                    .background(
                        brush = Brush.horizontalGradient(listOf(MtgGoldBright, MtgGold)),
                        shape = RoundedCornerShape(50)
                    )
                    .padding(horizontal = 12.dp, vertical = 4.dp)
            )

            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                TextButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("Game Code", code))
                }) {
                    Icon(Icons.Default.ContentCopy, null, tint = MtgGold, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Copy", color = MtgGold, fontSize = 12.sp)
                }

                TextButton(onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "Join my Treachery game! Code: $code")
                    }
                    context.startActivity(Intent.createChooser(intent, "Share game code"))
                }) {
                    Icon(Icons.Default.Share, null, tint = MtgGold, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Share", color = MtgGold, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun PlayerRow(
    player: Player,
    isMe: Boolean,
    isHost: Boolean,
    showColorPicker: Boolean,
    commanderNameInput: String,
    onToggleColorPicker: () -> Unit,
    onColorChange: (String?) -> Unit,
    onCommanderNameChange: (String) -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // Color bar
            player.playerColor?.let { hex ->
                val color = try { Color(android.graphics.Color.parseColor(hex)) } catch (_: Exception) { MtgTextSecondary }
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(32.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(color)
                )
                Spacer(Modifier.width(8.dp))
            }

            // Color picker toggle (for current player)
            if (isMe) {
                Box(
                    modifier = Modifier
                        .size(16.dp)
                        .clip(CircleShape)
                        .then(
                            if (player.playerColor != null) {
                                val color = try { Color(android.graphics.Color.parseColor(player.playerColor)) } catch (_: Exception) { MtgTextSecondary }
                                Modifier.background(color)
                            } else {
                                Modifier.background(Color.Transparent)
                            }
                        )
                        .clickable { onToggleColorPicker() },
                )
                Spacer(Modifier.width(6.dp))
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    player.displayName,
                    fontWeight = if (isHost) FontWeight.SemiBold else FontWeight.Normal,
                    color = MtgTextPrimary
                )
                if (!isMe && !player.commanderName.isNullOrEmpty()) {
                    Text(
                        player.commanderName!!,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Serif,
                        fontStyle = FontStyle.Italic,
                        color = MtgTextSecondary
                    )
                }
            }

            if (isHost) {
                Text(
                    "Host",
                    fontSize = 12.sp,
                    color = MtgGold,
                    modifier = Modifier
                        .background(MtgGold.copy(alpha = 0.15f), RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                )
            }
        }

        // Commander name field (for current player)
        if (isMe) {
            var localInput by remember(commanderNameInput) { mutableStateOf(commanderNameInput) }
            OutlinedTextField(
                value = localInput,
                onValueChange = {
                    localInput = it
                    onCommanderNameChange(it)
                },
                placeholder = { Text("Commander name...", fontSize = 12.sp, color = MtgTextSecondary) },
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                textStyle = androidx.compose.ui.text.TextStyle(
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                    color = MtgTextPrimary
                ),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = MtgCardElevated,
                    unfocusedContainerColor = MtgCardElevated,
                    focusedBorderColor = MtgDivider,
                    unfocusedBorderColor = MtgDivider,
                    cursorColor = MtgGold
                ),
                shape = RoundedCornerShape(6.dp)
            )
        }

        // Color picker
        AnimatedVisibility(
            visible = showColorPicker,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Row(
                modifier = Modifier.padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                PlayerColors.palette.forEach { playerColor ->
                    val isSelected = player.playerColor == playerColor.hex
                    Box(
                        modifier = Modifier
                            .size(24.dp)
                            .clip(CircleShape)
                            .background(playerColor.color)
                            .then(
                                if (isSelected) Modifier.background(Color.Transparent)
                                    .clip(CircleShape)
                                else Modifier
                            )
                            .clickable {
                                onColorChange(if (isSelected) null else playerColor.hex)
                            }
                    ) {
                        if (isSelected) {
                            Box(
                                Modifier.fillMaxSize()
                                    .padding(2.dp)
                                    .clip(CircleShape)
                                    .background(playerColor.color)
                            )
                        }
                    }
                }

                // Clear button
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .clickable { onColorChange(null) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Close, "Clear", tint = MtgTextSecondary, modifier = Modifier.size(12.dp))
                }
            }
        }
    }
}
