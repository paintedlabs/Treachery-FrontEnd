package com.solomon.treachery.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForgotPasswordScreen(
    authViewModel: AuthViewModel,
    onNavigateBack: () -> Unit
) {
    val errorMessage by authViewModel.errorMessage.collectAsState()
    var email by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var emailSent by remember { mutableStateOf(false) }

    LaunchedEffect(errorMessage) {
        if (errorMessage != null) isLoading = false
    }

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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Text(
                "Reset Password",
                style = MaterialTheme.typography.headlineMedium,
                color = MtgGoldBright
            )
            Text(
                "Enter your email to receive a reset link",
                style = MaterialTheme.typography.bodySmall,
                color = MtgTextSecondary
            )

            errorMessage?.let { MtgErrorBanner(it) }

            if (emailSent) {
                Text(
                    "Password reset email sent! Check your inbox.",
                    color = MtgSuccess,
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                MtgTextField(
                    value = email,
                    onValueChange = { email = it },
                    placeholder = "Email",
                    keyboardType = KeyboardType.Email,
                    enabled = !isLoading
                )

                MtgPrimaryButton(
                    text = if (isLoading) "Sending..." else "Send Reset Link",
                    onClick = {
                        if (email.isNotEmpty()) {
                            isLoading = true
                            authViewModel.resetPassword(email)
                            emailSent = true
                            isLoading = false
                        }
                    },
                    enabled = !isLoading,
                    isLoading = isLoading
                )
            }

            Spacer(modifier = Modifier.weight(1f))
        }
    }
}
