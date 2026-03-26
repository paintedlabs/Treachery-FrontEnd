package com.solomon.treachery.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.solomon.treachery.data.AnalyticsService
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FriendsListScreen(
    currentUserId: String?,
    onNavigateBack: () -> Unit,
    viewModel: FriendsViewModel = hiltViewModel()
) {
    val friends by viewModel.friends.collectAsState()
    val pendingRequests by viewModel.pendingRequests.collectAsState()
    val searchResults by viewModel.searchResults.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isSearching by viewModel.isSearching.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val sentRequestUserIds by viewModel.sentRequestUserIds.collectAsState()

    var searchText by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        AnalyticsService.trackScreen("Friends")
        currentUserId?.let { viewModel.loadData(it) }
    }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text("Friends", color = MtgGoldBright) },
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
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Search section
            MtgCardFrame {
                Column(modifier = Modifier.padding(bottom = 8.dp)) {
                    MtgSectionHeader(
                        "Add Friends",
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp)
                    )
                    OrnateDivider(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )

                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = searchText,
                            onValueChange = { searchText = it },
                            placeholder = {
                                Text(
                                    "Search by display name",
                                    color = MtgTextSecondary,
                                    fontSize = 14.sp
                                )
                            },
                            modifier = Modifier.weight(1f),
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = MtgTextPrimary,
                                unfocusedTextColor = MtgTextPrimary,
                                focusedContainerColor = MtgCardElevated,
                                unfocusedContainerColor = MtgCardElevated,
                                focusedBorderColor = MtgDivider,
                                unfocusedBorderColor = MtgDivider,
                                cursorColor = MtgGold
                            ),
                            shape = RoundedCornerShape(8.dp)
                        )
                        if (isSearching) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = MtgGold,
                                strokeWidth = 2.dp
                            )
                        } else if (searchText.isNotEmpty()) {
                            TextButton(onClick = { viewModel.searchUsers(searchText) }) {
                                Text("Search", color = MtgGold, fontSize = 14.sp)
                            }
                        }
                    }

                    // Search results
                    searchResults.filter { it.id != currentUserId }.forEach { user ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                user.displayName,
                                color = MtgTextPrimary,
                                modifier = Modifier.weight(1f)
                            )
                            when {
                                viewModel.isFriend(user.id) -> {
                                    Text(
                                        "Friends",
                                        fontSize = 12.sp,
                                        color = MtgSuccess
                                    )
                                }
                                sentRequestUserIds.contains(user.id) -> {
                                    Text(
                                        "Request Sent",
                                        fontSize = 12.sp,
                                        color = MtgGold
                                    )
                                }
                                else -> {
                                    TextButton(
                                        onClick = {
                                            currentUserId?.let {
                                                viewModel.sendRequest(it, user)
                                            }
                                        },
                                        contentPadding = PaddingValues(
                                            horizontal = 12.dp,
                                            vertical = 4.dp
                                        )
                                    ) {
                                        Text(
                                            "Add",
                                            fontSize = 12.sp,
                                            color = MtgBackground,
                                            modifier = Modifier
                                                .background(MtgGold, RoundedCornerShape(50))
                                                .padding(horizontal = 12.dp, vertical = 4.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Pending requests
            if (pendingRequests.isNotEmpty()) {
                MtgCardFrame {
                    Column {
                        MtgSectionHeader(
                            "Friend Requests (${pendingRequests.size})",
                            modifier = Modifier.padding(
                                start = 16.dp,
                                top = 16.dp,
                                bottom = 8.dp
                            )
                        )
                        OrnateDivider(
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )

                        pendingRequests.forEach { request ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        request.fromDisplayName,
                                        fontWeight = FontWeight.Medium,
                                        color = MtgTextPrimary
                                    )
                                    Text(
                                        "Wants to be friends",
                                        fontSize = 12.sp,
                                        color = MtgTextSecondary
                                    )
                                }
                                TextButton(
                                    onClick = {
                                        currentUserId?.let {
                                            viewModel.acceptRequest(it, request)
                                        }
                                    }
                                ) {
                                    Text(
                                        "Accept",
                                        fontSize = 12.sp,
                                        color = MtgBackground,
                                        modifier = Modifier
                                            .background(MtgSuccess, RoundedCornerShape(50))
                                            .padding(horizontal = 12.dp, vertical = 4.dp)
                                    )
                                }
                                TextButton(onClick = { viewModel.declineRequest(request) }) {
                                    Text(
                                        "Decline",
                                        fontSize = 12.sp,
                                        color = MtgTextSecondary
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Friends list
            MtgCardFrame {
                Column {
                    MtgSectionHeader(
                        "Friends (${friends.size})",
                        modifier = Modifier.padding(
                            start = 16.dp,
                            top = 16.dp,
                            bottom = 8.dp
                        )
                    )
                    OrnateDivider(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )

                    if (isLoading) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                color = MtgGold,
                                modifier = Modifier.size(24.dp)
                            )
                        }
                    } else if (friends.isEmpty()) {
                        Text(
                            "No friends yet. Search for players above.",
                            color = MtgTextSecondary,
                            fontSize = 14.sp,
                            modifier = Modifier.padding(16.dp)
                        )
                    } else {
                        friends.forEachIndexed { index, friend ->
                            Text(
                                friend.displayName,
                                color = MtgTextPrimary,
                                modifier = Modifier.padding(
                                    horizontal = 16.dp,
                                    vertical = 10.dp
                                )
                            )
                            if (index < friends.lastIndex) {
                                HorizontalDivider(
                                    color = MtgDivider,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
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
