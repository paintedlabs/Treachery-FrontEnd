package com.solomon.treachery.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.solomon.treachery.model.Role
import com.solomon.treachery.ui.theme.*

@Composable
fun WelcomeScreen(onComplete: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    val scrollState = rememberScrollState()

    val roles = listOf(
        Triple(Role.LEADER, Role.LEADER.roleColor, Role.LEADER.winConditionText),
        Triple(Role.GUARDIAN, Role.GUARDIAN.roleColor, Role.GUARDIAN.winConditionText),
        Triple(Role.ASSASSIN, Role.ASSASSIN.roleColor, Role.ASSASSIN.winConditionText),
        Triple(Role.TRAITOR, Role.TRAITOR.roleColor, Role.TRAITOR.winConditionText),
    )

    Box(modifier = Modifier.fillMaxSize()) {
        MtgRadialBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(scrollState)
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(48.dp))

            MtgGoldShimmerText(
                text = "Welcome to Treachery",
                fontSize = 28f,
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "A Game of Hidden Allegiance",
                color = MtgTextSecondary,
                fontSize = 14.sp,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(24.dp))

            Text(
                text = "Each player is secretly assigned a role. Use deception and strategy to achieve your team's goal.",
                color = MtgTextSecondary,
                fontSize = 14.sp,
                fontFamily = FontFamily.Serif,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 8.dp),
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Role cards 2x2 grid
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    RoleCard(roles[0], Modifier.weight(1f))
                    RoleCard(roles[1], Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    RoleCard(roles[2], Modifier.weight(1f))
                    RoleCard(roles[3], Modifier.weight(1f))
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            TextButton(onClick = { uriHandler.openUri("https://mtgtreachery.net") }) {
                Text(
                    text = "Read the full rules at mtgtreachery.net",
                    color = MtgGold,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            MtgPrimaryButton(
                text = "Let's Play",
                onClick = onComplete,
            )

            Spacer(modifier = Modifier.height(48.dp))
        }
    }
}

@Composable
private fun RoleCard(
    roleData: Triple<Role, Color, String>,
    modifier: Modifier = Modifier,
) {
    val (role, color, description) = roleData
    val shape = RoundedCornerShape(10.dp)

    Box(
        modifier = modifier
            .clip(shape)
            .border(1.dp, color.copy(alpha = 0.3f), shape)
            .background(MtgSurface)
    ) {
        // Left accent bar
        Box(
            modifier = Modifier
                .width(3.dp)
                .fillMaxHeight()
                .background(color)
                .align(Alignment.CenterStart)
        )

        Column(
            modifier = Modifier.padding(start = 14.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
        ) {
            Text(
                text = role.displayName,
                color = color,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Serif,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = description,
                color = MtgTextSecondary,
                fontSize = 11.sp,
                fontFamily = FontFamily.Serif,
                lineHeight = 15.sp,
            )
        }
    }
}
