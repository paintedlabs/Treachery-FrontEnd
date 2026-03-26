package com.solomon.treachery.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameHistoryScreen(
    currentUserId: String?,
    onNavigateBack: () -> Unit,
    viewModel: GameHistoryViewModel = hiltViewModel()
) {
    val games by viewModel.games.collectAsState()
    val gamePlayers by viewModel.gamePlayers.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("GameHistory")
        currentUserId?.let { viewModel.loadHistory(it) }
    }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text("Game History", color = MtgGoldBright) },
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            when {
                isLoading -> {
                    Spacer(Modifier.height(80.dp))
                    Box(
                        modifier = Modifier.fillMaxWidth(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = MtgGold)
                    }
                }
                games.isEmpty() -> {
                    Spacer(Modifier.height(60.dp))
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            Icons.Default.HelpOutline,
                            contentDescription = null,
                            tint = MtgTextSecondary,
                            modifier = Modifier.size(48.dp)
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            "No games yet",
                            fontWeight = FontWeight.Bold,
                            color = MtgTextPrimary
                        )
                        Text(
                            "Finished games will appear here.",
                            fontSize = 14.sp,
                            color = MtgTextSecondary
                        )
                    }
                }
                else -> {
                    val dateFormat = remember {
                        SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
                    }
                    val timeFormat = remember {
                        SimpleDateFormat("h:mm a", Locale.getDefault())
                    }

                    games.forEach { game ->
                        val players = gamePlayers[game.id] ?: emptyList()
                        val winRole = game.winningTeam?.let { Role.fromValue(it) }
                        val myPlayer = players.find { it.userId == currentUserId }
                        val myRole = myPlayer?.role
                        val didWin = if (winRole != null && myRole != null) {
                            if (winRole == Role.LEADER) {
                                myRole == Role.LEADER || myRole == Role.GUARDIAN
                            } else {
                                myRole == winRole
                            }
                        } else {
                            false
                        }

                        MtgCardFrame {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                // Header row: date/time on left, result on right
                                Row(modifier = Modifier.fillMaxWidth()) {
                                    Column {
                                        Text(
                                            dateFormat.format(game.createdAt.toDate()),
                                            fontWeight = FontWeight.Medium,
                                            color = MtgTextPrimary,
                                            fontSize = 14.sp
                                        )
                                        Text(
                                            timeFormat.format(game.createdAt.toDate()),
                                            fontSize = 12.sp,
                                            color = MtgTextSecondary
                                        )
                                    }
                                    Spacer(Modifier.weight(1f))
                                    winRole?.let { wr ->
                                        Column(
                                            horizontalAlignment = Alignment.End
                                        ) {
                                            Text(
                                                if (didWin) "Victory" else "Defeat",
                                                fontWeight = FontWeight.Bold,
                                                color = if (didWin) MtgSuccess else MtgError,
                                                fontSize = 14.sp
                                            )
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(8.dp)
                                                        .clip(CircleShape)
                                                        .background(wr.roleColor)
                                                )
                                                Text(
                                                    "${wr.displayName} Won",
                                                    fontSize = 12.sp,
                                                    color = wr.roleColor
                                                )
                                            }
                                        }
                                    }
                                }

                                // Player grid
                                if (players.isNotEmpty()) {
                                    OrnateDivider()

                                    val chunked = players.chunked(2)
                                    chunked.forEach { row ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                                        ) {
                                            row.forEach { player ->
                                                Row(
                                                    modifier = Modifier.weight(1f),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                                ) {
                                                    Box(
                                                        modifier = Modifier
                                                            .size(6.dp)
                                                            .clip(CircleShape)
                                                            .background(
                                                                player.role?.roleColor
                                                                    ?: MtgTextSecondary
                                                            )
                                                    )
                                                    Text(
                                                        player.displayName,
                                                        fontSize = 12.sp,
                                                        maxLines = 1,
                                                        color = if (player.userId == currentUserId) {
                                                            MtgTextPrimary
                                                        } else {
                                                            MtgTextSecondary
                                                        },
                                                        fontWeight = if (player.userId == currentUserId) {
                                                            FontWeight.SemiBold
                                                        } else {
                                                            FontWeight.Normal
                                                        }
                                                    )
                                                    if (player.isEliminated) {
                                                        Icon(
                                                            Icons.Default.Cancel,
                                                            contentDescription = null,
                                                            tint = MtgError,
                                                            modifier = Modifier.size(8.dp)
                                                        )
                                                    }
                                                }
                                            }
                                            // Fill empty space in odd-count rows
                                            if (row.size == 1) {
                                                Spacer(Modifier.weight(1f))
                                            }
                                        }
                                    }
                                }

                                // Your role footer
                                myRole?.let { role ->
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                                    ) {
                                        Text(
                                            "Your role:",
                                            fontSize = 10.sp,
                                            color = MtgTextSecondary
                                        )
                                        Text(
                                            role.displayName,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.SemiBold,
                                            color = role.roleColor
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Error banner
            errorMessage?.let { MtgErrorBanner(it) }
        }
    }
}
