package com.solomon.treachery.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.ui.auth.AuthViewModel
import com.solomon.treachery.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    authViewModel: AuthViewModel,
    onNavigateBack: () -> Unit,
    onNavigateToFriends: () -> Unit,
    onNavigateToHistory: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val user by viewModel.user.collectAsState()
    val gameStats by viewModel.gameStats.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val isSaving by viewModel.isSaving.collectAsState()

    var isEditing by remember { mutableStateOf(false) }
    var editedName by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("Profile")
        authViewModel.currentUserId?.let { viewModel.loadData(it) }
    }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text("Profile", color = MtgGoldBright) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MtgGold)
                    }
                },
                actions = {
                    if (isEditing) {
                        TextButton(
                            onClick = {
                                viewModel.saveName(editedName)
                                isEditing = false
                            },
                            enabled = editedName.isNotBlank() && !isSaving
                        ) {
                            Text(if (isSaving) "Saving..." else "Save", color = MtgGold)
                        }
                    } else {
                        TextButton(
                            onClick = {
                                editedName = user?.displayName ?: ""
                                isEditing = true
                            },
                            enabled = user != null
                        ) {
                            Text("Edit", color = MtgGold)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MtgBackground)
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize()) {
            MtgRadialBackground()

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // Profile info card
                MtgCardFrame {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        MtgSectionHeader("Profile", modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp))
                        OrnateDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

                        user?.let { u ->
                            // Display name
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Display Name", color = MtgTextPrimary)
                                Spacer(Modifier.weight(1f))
                                if (isEditing) {
                                    OutlinedTextField(
                                        value = editedName,
                                        onValueChange = { editedName = it },
                                        modifier = Modifier.width(160.dp),
                                        singleLine = true,
                                        textStyle = TextStyle(color = MtgGoldBright, textAlign = TextAlign.End),
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedBorderColor = MtgGold,
                                            unfocusedBorderColor = MtgDivider,
                                            cursorColor = MtgGold,
                                            focusedContainerColor = MtgCardElevated,
                                            unfocusedContainerColor = MtgCardElevated
                                        ),
                                        shape = RoundedCornerShape(6.dp)
                                    )
                                } else {
                                    Text(u.displayName, color = MtgTextSecondary)
                                }
                            }

                            // Member since
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Member Since", color = MtgTextPrimary)
                                Spacer(Modifier.weight(1f))
                                val dateFormat = remember { SimpleDateFormat("MMM d, yyyy", Locale.getDefault()) }
                                Text(dateFormat.format(u.createdAt.toDate()), color = MtgTextSecondary)
                            }

                            Spacer(Modifier.height(8.dp))
                        } ?: run {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(color = MtgGold, modifier = Modifier.size(24.dp))
                            }
                        }
                    }
                }

                // Game stats card
                MtgCardFrame {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        MtgSectionHeader("Game Stats", modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp))
                        OrnateDivider(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

                        gameStats?.let { stats ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                MtgStatBox("${stats.totalGames}", "Games", modifier = Modifier.weight(1f))
                                MtgStatBox("${stats.wins}", "Wins", modifier = Modifier.weight(1f), color = MtgSuccess)
                                MtgStatBox("${stats.losses}", "Losses", modifier = Modifier.weight(1f), color = MtgError)
                                MtgStatBox(stats.winRateText, "Win %", modifier = Modifier.weight(1f), color = MtgGuardian)
                            }

                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                MtgStatBox("${user?.elo ?: 1500}", "ELO", modifier = Modifier.weight(1f), color = MtgGoldBright)
                            }

                            // Role breakdown
                            if (stats.roleBreakdown.isNotEmpty()) {
                                Column(
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Text("Roles Played", fontSize = 12.sp, color = MtgTextSecondary)
                                    stats.roleBreakdown.entries.sortedByDescending { it.value }.forEach { (role, count) ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Box(
                                                Modifier
                                                    .size(8.dp)
                                                    .clip(CircleShape)
                                                    .background(role.roleColor)
                                            )
                                            Spacer(Modifier.width(6.dp))
                                            Text(role.displayName, fontSize = 14.sp, color = MtgTextPrimary)
                                            Spacer(Modifier.weight(1f))
                                            Text("$count", fontSize = 14.sp, color = MtgTextSecondary)
                                        }
                                    }
                                }
                            }

                            // View history link
                            TextButton(
                                onClick = onNavigateToHistory,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("View Game History", color = MtgGold)
                                Spacer(Modifier.weight(1f))
                                Icon(Icons.Default.ChevronRight, null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
                            }

                            Spacer(Modifier.height(8.dp))
                        } ?: run {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(color = MtgGold, modifier = Modifier.size(24.dp))
                            }
                        }
                    }
                }

                // Friends link
                user?.let { u ->
                    MtgCardFrame {
                        TextButton(
                            onClick = onNavigateToFriends,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp)
                        ) {
                            Text("Friends", color = MtgTextPrimary)
                            Spacer(Modifier.weight(1f))
                            Text("${u.friendIds.size}", color = MtgTextSecondary)
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Default.ChevronRight, null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
                        }
                    }
                }

                // Error
                errorMessage?.let {
                    MtgCardFrame(borderColor = MtgError) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            MtgErrorBanner("Error loading profile")
                            Spacer(Modifier.height(4.dp))
                            Text(it, color = MtgError, fontSize = 12.sp)
                        }
                    }
                }

                // Sign out
                MtgCardFrame(borderColor = MtgError.copy(alpha = 0.5f)) {
                    TextButton(
                        onClick = { authViewModel.signOut() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp)
                    ) {
                        Text("Sign Out", color = MtgError)
                    }
                }
            }
        }
    }
}
