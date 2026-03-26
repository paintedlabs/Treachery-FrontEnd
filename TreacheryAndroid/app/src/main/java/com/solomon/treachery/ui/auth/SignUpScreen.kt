package com.solomon.treachery.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solomon.treachery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SignUpScreen(
    authViewModel: AuthViewModel,
    onNavigateBack: () -> Unit
) {
    val errorMessage by authViewModel.errorMessage.collectAsState()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(errorMessage) {
        if (errorMessage != null) isLoading = false
    }

    Scaffold(
        containerColor = MtgBackground,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    if (!isLoading) {
                        IconButton(onClick = onNavigateBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MtgGold)
                        }
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
                "Create Account",
                style = MaterialTheme.typography.headlineMedium,
                color = MtgGoldBright
            )
            Text(
                "Join the game of hidden allegiance",
                style = MaterialTheme.typography.bodySmall.copy(
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic
                ),
                color = MtgTextSecondary
            )

            val displayError = localError ?: errorMessage
            displayError?.let { MtgErrorBanner(it) }

            MtgTextField(
                value = email,
                onValueChange = { email = it },
                placeholder = "Email",
                keyboardType = KeyboardType.Email,
                enabled = !isLoading
            )

            MtgTextField(
                value = password,
                onValueChange = { password = it },
                placeholder = "Password",
                isSecure = true,
                enabled = !isLoading
            )

            MtgTextField(
                value = confirmPassword,
                onValueChange = { confirmPassword = it },
                placeholder = "Confirm Password",
                isSecure = true,
                enabled = !isLoading
            )

            MtgPrimaryButton(
                text = if (isLoading) "Creating Account..." else "Create Account",
                onClick = {
                    localError = null
                    authViewModel.clearError()
                    when {
                        email.isEmpty() || password.isEmpty() -> return@MtgPrimaryButton
                        password != confirmPassword -> localError = "Passwords do not match."
                        password.length < 6 -> localError = "Password must be at least 6 characters."
                        else -> {
                            isLoading = true
                            authViewModel.signUp(email, password)
                        }
                    }
                },
                enabled = !isLoading,
                isLoading = isLoading
            )

            TextButton(onClick = onNavigateBack, enabled = !isLoading) {
                Text("Already have an account? Sign In", color = MtgGold, fontSize = 14.sp)
            }

            Spacer(modifier = Modifier.weight(1f))
        }
    }
}
