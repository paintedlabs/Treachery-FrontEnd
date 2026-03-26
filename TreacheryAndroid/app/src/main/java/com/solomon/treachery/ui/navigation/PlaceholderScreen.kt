package com.solomon.treachery.ui.navigation

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaceholderScreen(title: String, onBack: () -> Unit) {
    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = { Text(title, color = MtgGoldBright) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MtgGold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MtgBackground)
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "Coming soon",
                style = MaterialTheme.typography.bodyLarge,
                color = MtgTextSecondary
            )
        }
    }
}
