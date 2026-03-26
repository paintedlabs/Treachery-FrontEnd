package com.solomon.treachery.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhoneAuthScreen(
    onNavigateBack: () -> Unit
) {
    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = {},
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
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                "Phone Sign In",
                style = MaterialTheme.typography.headlineMedium,
                color = MtgGoldBright
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                "Phone authentication coming soon.\nPlease use email or guest sign in for now.",
                style = MaterialTheme.typography.bodyMedium,
                color = MtgTextSecondary
            )
            Spacer(modifier = Modifier.height(24.dp))
            MtgSecondaryButton(
                text = "Go Back",
                onClick = onNavigateBack
            )
        }
    }
}
