package com.solomon.treachery.ui.home

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JoinGameScreen(
    currentUserId: String?,
    onNavigateBack: () -> Unit,
    onNavigateToLobby: (gameId: String, isHost: Boolean) -> Unit,
    viewModel: JoinGameViewModel = hiltViewModel()
) {
    var gameCode by remember { mutableStateOf("") }
    val isJoining by viewModel.isJoining.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    LaunchedEffect(Unit) { AnalyticsService.trackScreen("JoinGame") }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text("Join Game", color = MtgGoldBright) },
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
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(20.dp))

            MtgCardFrame(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    MtgSectionHeader("Enter Game Code")
                    OrnateDivider()
                    Text("Enter the 4-character game code", style = MaterialTheme.typography.bodySmall, color = MtgTextSecondary)

                    OutlinedTextField(
                        value = gameCode,
                        onValueChange = { gameCode = it.uppercase().take(4) },
                        modifier = Modifier.fillMaxWidth(),
                        textStyle = TextStyle(
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            fontSize = 32.sp,
                            textAlign = TextAlign.Center,
                            color = MtgGoldBright
                        ),
                        placeholder = {
                            Text(
                                "ABCD",
                                modifier = Modifier.fillMaxWidth(),
                                textAlign = TextAlign.Center,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                                fontSize = 32.sp,
                                color = MtgTextSecondary.copy(alpha = 0.3f)
                            )
                        },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = MtgCardElevated,
                            unfocusedContainerColor = MtgCardElevated,
                            focusedBorderColor = MtgGold,
                            unfocusedBorderColor = MtgGold,
                            cursorColor = MtgGold
                        ),
                        shape = RoundedCornerShape(8.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            errorMessage?.let {
                MtgErrorBanner(it)
                Spacer(modifier = Modifier.height(16.dp))
            }

            MtgPrimaryButton(
                text = if (isJoining) "Joining..." else "Join Game",
                onClick = {
                    val userId = currentUserId ?: return@MtgPrimaryButton
                    viewModel.joinGame(userId, gameCode) { gameId, isHost ->
                        onNavigateToLobby(gameId, isHost)
                    }
                },
                enabled = gameCode.length >= 4 && !isJoining,
                isLoading = isJoining
            )

            Spacer(modifier = Modifier.weight(1f))
        }
    }
}
