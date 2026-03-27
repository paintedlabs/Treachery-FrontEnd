package com.solomon.treachery.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solomon.treachery.ui.theme.*

@Composable
fun DisplayNamePromptScreen(
    authViewModel: AuthViewModel,
    onContinue: () -> Unit,
    onSkip: () -> Unit
) {
    val authState by authViewModel.authState.collectAsState()
    var displayName by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var validationError by remember { mutableStateOf<String?>(null) }

    // Pre-fill from email
    LaunchedEffect(authState) {
        val user = (authState as? AuthState.Authenticated)?.user ?: return@LaunchedEffect
        if (displayName.isNotEmpty()) return@LaunchedEffect
        displayName = when {
            !user.email.isNullOrEmpty() -> {
                val prefix = user.email!!.substringBefore("@")
                prefix.replaceFirstChar { it.uppercase() }
            }
            user.isAnonymous -> "Guest"
            else -> "Player"
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MtgRadialBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "Choose Your Name",
                color = MtgGoldBright,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Serif,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "This is how other players will see you",
                color = MtgTextSecondary,
                fontSize = 14.sp,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(24.dp))

            MtgTextField(
                value = displayName,
                onValueChange = {
                    displayName = it
                    validationError = null
                },
                placeholder = "Display Name",
                enabled = !isSaving,
            )

            if (validationError != null) {
                Spacer(modifier = Modifier.height(8.dp))
                MtgErrorBanner(message = validationError!!)
            }

            Spacer(modifier = Modifier.height(16.dp))

            MtgPrimaryButton(
                text = if (isSaving) "Saving..." else "Continue",
                onClick = {
                    val trimmed = displayName.trim()
                    if (trimmed.isEmpty()) {
                        validationError = "Please enter a display name."
                        return@MtgPrimaryButton
                    }
                    validationError = null
                    isSaving = true
                    authViewModel.updateDisplayName(trimmed)
                    isSaving = false
                    onContinue()
                },
                enabled = !isSaving,
            )

            Spacer(modifier = Modifier.height(16.dp))

            TextButton(onClick = onSkip, enabled = !isSaving) {
                Text(
                    text = "Skip",
                    color = MtgGold,
                    fontFamily = FontFamily.Serif,
                    fontSize = 14.sp,
                )
            }

            Spacer(modifier = Modifier.weight(1f))
        }
    }
}
