package com.solomon.treachery.ui.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solomon.treachery.ui.theme.*

@Composable
fun LoginScreen(
    authViewModel: AuthViewModel,
    onNavigateToSignUp: () -> Unit,
    onNavigateToForgotPassword: () -> Unit
) {
    val errorMessage by authViewModel.errorMessage.collectAsState()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var isGuestLoading by remember { mutableStateOf(false) }
    var formVisible by remember { mutableStateOf(false) }

    val busy = isLoading || isGuestLoading

    LaunchedEffect(Unit) { formVisible = true }

    // Reset loading when error appears
    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            isLoading = false
            isGuestLoading = false
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MtgRadialBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .statusBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Title
            MtgGoldShimmerText("Treachery")
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "A Game of Hidden Allegiance",
                style = MaterialTheme.typography.bodySmall,
                color = MtgTextSecondary
            )
            Spacer(modifier = Modifier.height(4.dp))
            OrnateDivider(modifier = Modifier.padding(vertical = 4.dp))

            Spacer(modifier = Modifier.height(32.dp))

            // Form with fade-in
            AnimatedVisibility(
                visible = formVisible,
                enter = fadeIn() + slideInVertically(initialOffsetY = { 12 })
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    errorMessage?.let { MtgErrorBanner(it) }

                    MtgTextField(
                        value = email,
                        onValueChange = { email = it },
                        placeholder = "Email",
                        keyboardType = KeyboardType.Email,
                        enabled = !busy
                    )

                    MtgTextField(
                        value = password,
                        onValueChange = { password = it },
                        placeholder = "Password",
                        isSecure = true,
                        enabled = !busy
                    )

                    MtgPrimaryButton(
                        text = if (isLoading) "Signing In..." else "Sign In",
                        onClick = {
                            if (email.isNotEmpty() && password.isNotEmpty()) {
                                isLoading = true
                                authViewModel.signIn(email, password)
                            }
                        },
                        enabled = !busy,
                        isLoading = isLoading
                    )

                    // Links row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        TextButton(onClick = onNavigateToSignUp, enabled = !busy) {
                            Text("Create Account", color = MtgGold, fontSize = 14.sp)
                        }
                        TextButton(onClick = onNavigateToForgotPassword, enabled = !busy) {
                            Text("Forgot Password?", color = MtgGold, fontSize = 14.sp)
                        }
                    }

                    // Divider
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        HorizontalDivider(modifier = Modifier.weight(1f), color = MtgDivider)
                        Text("or", style = MaterialTheme.typography.bodySmall, color = MtgTextSecondary)
                        HorizontalDivider(modifier = Modifier.weight(1f), color = MtgDivider)
                    }

                    // Guest button
                    MtgSecondaryButton(
                        text = if (isGuestLoading) "Joining..." else "Play as Guest",
                        onClick = {
                            isGuestLoading = true
                            authViewModel.signInAsGuest()
                        },
                        enabled = !busy,
                        isLoading = isGuestLoading
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Footer link
            val uriHandler = LocalUriHandler.current
            TextButton(onClick = { uriHandler.openUri("https://mtgtreachery.net") }) {
                Text(
                    "Learn the rules at MTGTreachery.net",
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Serif,
                        fontStyle = FontStyle.Italic
                    ),
                    color = MtgTextSecondary,
                    textAlign = TextAlign.Center
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}
