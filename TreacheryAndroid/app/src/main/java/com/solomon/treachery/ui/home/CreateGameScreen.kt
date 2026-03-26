package com.solomon.treachery.ui.home

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateGameScreen(
    currentUserId: String?,
    onNavigateBack: () -> Unit,
    onNavigateToLobby: (gameId: String, isHost: Boolean) -> Unit,
    viewModel: CreateGameViewModel = hiltViewModel()
) {
    var gameMode by remember { mutableStateOf(GameMode.TREACHERY) }
    var useOwnDeck by remember { mutableStateOf(false) }
    var startingLife by remember { mutableIntStateOf(40) }

    val isCreating by viewModel.isCreating.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    LaunchedEffect(Unit) { AnalyticsService.trackScreen("CreateGame") }

    LaunchedEffect(gameMode) {
        if (!gameMode.includesPlanechase) useOwnDeck = false
    }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text("Create Game", color = MtgGoldBright) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MtgGold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MtgBackground)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Game Mode selector
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MtgSectionHeader("Game Mode")
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    GameMode.entries.forEachIndexed { index, mode ->
                        SegmentedButton(
                            selected = gameMode == mode,
                            onClick = { gameMode = mode },
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = GameMode.entries.size),
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = MtgGold,
                                activeContentColor = MtgBackground,
                                inactiveContainerColor = MtgSurface,
                                inactiveContentColor = MtgTextSecondary,
                                activeBorderColor = MtgGold,
                                inactiveBorderColor = MtgDivider
                            )
                        ) {
                            Text(mode.displayName, fontSize = 12.sp)
                        }
                    }
                }
            }

            if (gameMode.includesPlanechase) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("I have my own planar deck", color = MtgTextPrimary)
                    Switch(
                        checked = useOwnDeck,
                        onCheckedChange = { useOwnDeck = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = MtgBackground,
                            checkedTrackColor = MtgGold,
                            uncheckedThumbColor = MtgTextSecondary,
                            uncheckedTrackColor = MtgSurface
                        )
                    )
                }
            }

            MtgCardFrame {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    MtgSectionHeader("Game Settings")
                    OrnateDivider()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Starting Life: $startingLife", color = MtgTextPrimary)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilledIconButton(
                                onClick = { if (startingLife > 20) startingLife -= 5 },
                                colors = IconButtonDefaults.filledIconButtonColors(containerColor = MtgCardElevated, contentColor = MtgGold),
                                modifier = Modifier.size(36.dp)
                            ) { Icon(Icons.Default.Remove, "Decrease", modifier = Modifier.size(18.dp)) }
                            FilledIconButton(
                                onClick = { if (startingLife < 60) startingLife += 5 },
                                colors = IconButtonDefaults.filledIconButtonColors(containerColor = MtgCardElevated, contentColor = MtgGold),
                                modifier = Modifier.size(36.dp)
                            ) { Icon(Icons.Default.Add, "Increase", modifier = Modifier.size(18.dp)) }
                        }
                    }
                }
            }

            errorMessage?.let { MtgErrorBanner(it) }

            MtgPrimaryButton(
                text = if (isCreating) "Creating..." else "Create Game",
                onClick = {
                    val userId = currentUserId ?: return@MtgPrimaryButton
                    viewModel.createGame(userId, gameMode, startingLife, useOwnDeck) { gameId ->
                        onNavigateToLobby(gameId, true)
                    }
                },
                enabled = !isCreating,
                isLoading = isCreating
            )
        }
    }
}
