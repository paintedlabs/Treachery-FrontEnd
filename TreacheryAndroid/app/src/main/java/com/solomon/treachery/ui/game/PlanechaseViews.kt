package com.solomon.treachery.ui.game

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.solomon.treachery.model.PlaneCard
import com.solomon.treachery.ui.theme.*

// MARK: - Plane Card Banner

@Composable
fun PlaneCardBanner(
    plane: PlaneCard,
    secondaryPlane: PlaneCard? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(MtgSurface)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            if (plane.isPhenomenon) Icons.Default.AutoAwesome else Icons.Default.Public,
            contentDescription = null,
            tint = MtgGold
        )

        Column(modifier = Modifier.weight(1f)) {
            Text(
                plane.name,
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.SemiBold,
                color = MtgTextPrimary,
                maxLines = 1
            )

            secondaryPlane?.let { secondary ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("+", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MtgGold)
                    Text(secondary.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary, maxLines = 1)
                }
            }

            Text(plane.typeLine, fontSize = 10.sp, color = MtgTextSecondary, maxLines = 1)
        }

        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
    }
}

// MARK: - Plane Card Detail Sheet

@Composable
fun PlaneCardDetailSheet(plane: PlaneCard, onDismiss: () -> Unit) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Scaffold(containerColor = MtgBackground) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
            ) {
                // Close button
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.End
                ) {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, "Close", tint = MtgTextSecondary)
                    }
                }

                // Image placeholder
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(240.dp)
                        .padding(horizontal = 16.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(MtgCardElevated),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (plane.isPhenomenon) Icons.Default.AutoAwesome else Icons.Default.Public,
                        contentDescription = null,
                        tint = MtgTextSecondary,
                        modifier = Modifier.size(48.dp)
                    )
                }

                Spacer(Modifier.height(16.dp))

                // Card info
                Column(modifier = Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(plane.name, fontSize = 24.sp, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, color = MtgTextPrimary)

                    Text(plane.typeLine, fontSize = 14.sp, color = MtgGold)

                    if (plane.isPhenomenon) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier
                                .background(MtgGoldBright.copy(alpha = 0.15f), RoundedCornerShape(50))
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Icon(Icons.Default.AutoAwesome, null, tint = MtgGoldBright, modifier = Modifier.size(14.dp))
                            Text("PHENOMENON", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = MtgGoldBright, letterSpacing = 1.2.sp)
                        }
                    }

                    HorizontalDivider(color = MtgDivider)

                    Text(plane.oracleText, color = MtgTextPrimary, lineHeight = 22.sp)
                }

                Spacer(Modifier.height(40.dp))
            }
        }
    }
}

// MARK: - Planar Die Bar

@Composable
fun PlanarDieBar(
    dieRollResult: String?,
    isRollingDie: Boolean,
    dieRollCost: Int,
    lastDieRollerName: String?,
    isPending: Boolean,
    onRollDie: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MtgSurface)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Die result display
        AnimatedVisibility(
            visible = dieRollResult != null,
            enter = scaleIn() + fadeIn(),
            exit = scaleOut() + fadeOut()
        ) {
            dieRollResult?.let { result ->
                val resultColor = when (result) {
                    "chaos" -> MtgAssassin
                    "planeswalk" -> MtgGuardian
                    else -> MtgTextSecondary
                }
                val resultLabel = when (result) {
                    "chaos" -> "Chaos!"
                    "planeswalk" -> "Planeswalk!"
                    else -> "Blank"
                }
                val resultIcon = when (result) {
                    "chaos" -> Icons.Default.FlashOn
                    "planeswalk" -> Icons.Default.ArrowCircleRight
                    else -> Icons.Default.Circle
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(resultColor.copy(alpha = 0.12f))
                        .border(1.dp, resultColor.copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                        .padding(vertical = 8.dp, horizontal = 20.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(resultIcon, null, tint = resultColor, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(resultLabel, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, color = resultColor, fontSize = 18.sp)
                }
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Roll button
            Button(
                onClick = onRollDie,
                enabled = !isRollingDie && !isPending,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRollingDie) MtgGold.copy(alpha = 0.4f) else MtgGold,
                    contentColor = MtgBackground,
                    disabledContainerColor = MtgGold.copy(alpha = 0.4f),
                    disabledContentColor = MtgBackground
                ),
                contentPadding = PaddingValues(vertical = 12.dp)
            ) {
                if (isRollingDie) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = MtgBackground, strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                } else {
                    Icon(Icons.Default.Casino, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                }
                Text("Roll Planar Die", fontWeight = FontWeight.SemiBold)
            }

            // Mana cost
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(50.dp)) {
                Text(
                    "$dieRollCost",
                    fontSize = 22.sp,
                    fontFamily = FontFamily.Serif,
                    fontWeight = FontWeight.Bold,
                    color = if (dieRollCost > 0) MtgGold else MtgTextSecondary
                )
                Text("Mana", fontSize = 10.sp, color = MtgTextSecondary)
            }
        }

        // Last roller
        lastDieRollerName?.let { name ->
            Text("Last roll by $name", fontSize = 10.sp, color = MtgTextSecondary, fontStyle = FontStyle.Italic)
        }
    }
}

// MARK: - Phenomenon Overlay

@Composable
fun PhenomenonOverlay(
    plane: PlaneCard,
    isPending: Boolean,
    onResolve: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MtgSurface)
            .background(Brush.verticalGradient(listOf(MtgGoldBright.copy(alpha = 0.2f), Color.Transparent), endY = 4f))
            .border(1.dp, MtgGoldBright, RoundedCornerShape(0.dp))
            .padding(vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.AutoAwesome, null, tint = MtgGoldBright)
            Text("PHENOMENON", fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, color = MtgGoldBright, letterSpacing = 1.5.sp)
            Icon(Icons.Default.AutoAwesome, null, tint = MtgGoldBright)
        }

        Text(plane.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary, fontSize = 18.sp)

        Text(
            plane.oracleText,
            fontSize = 14.sp,
            color = MtgTextSecondary,
            textAlign = TextAlign.Center,
            lineHeight = 20.sp,
            modifier = Modifier.padding(horizontal = 24.dp)
        )

        MtgPrimaryButton(
            text = if (isPending) "Resolving..." else "Resolve Phenomenon",
            onClick = onResolve,
            enabled = !isPending,
            isLoading = isPending,
            modifier = Modifier.padding(horizontal = 40.dp)
        )
    }
}

// MARK: - Interplanar Tunnel Picker

@Composable
fun InterplanarTunnelPicker(
    options: List<PlaneCard>,
    isPending: Boolean,
    onSelectPlane: (PlaneCard) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Scaffold(containerColor = MtgBackground) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Spacer(Modifier.height(24.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.AltRoute, null, tint = MtgGold)
                    Text("Interplanar Tunnel", fontSize = 24.sp, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, color = MtgTextPrimary)
                }
                Spacer(Modifier.height(6.dp))
                Text("Choose your next destination", fontSize = 14.sp, color = MtgTextSecondary)

                Spacer(Modifier.height(16.dp))
                HorizontalDivider(color = MtgDivider, modifier = Modifier.padding(horizontal = 16.dp))
                Spacer(Modifier.height(16.dp))

                // Plane options
                Column(
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .border(1.dp, MtgBorderAccent, RoundedCornerShape(12.dp))
                ) {
                    options.forEachIndexed { index, plane ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(enabled = !isPending) { onSelectPlane(plane) }
                                .background(MtgSurface)
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(Icons.Default.Public, null, tint = MtgGold, modifier = Modifier.size(24.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(plane.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary, maxLines = 1)
                                Text(plane.typeLine, fontSize = 12.sp, color = MtgTextSecondary, maxLines = 1)
                            }
                            Icon(Icons.Default.ChevronRight, null, tint = MtgTextSecondary, modifier = Modifier.size(16.dp))
                        }
                        if (index < options.lastIndex) {
                            HorizontalDivider(color = MtgDivider, modifier = Modifier.padding(horizontal = 16.dp))
                        }
                    }
                }

                if (isPending) {
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(14.dp), color = MtgGold, strokeWidth = 2.dp)
                        Text("Traveling...", fontSize = 14.sp, color = MtgTextSecondary)
                    }
                }

                Spacer(Modifier.weight(1f))
            }
        }
    }
}

// MARK: - Chaotic Aether Indicator

@Composable
fun ChaoticAetherIndicator() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MtgGoldBright.copy(alpha = 0.12f))
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.FlashOn, null, tint = MtgGoldBright, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(8.dp))
        Text("Chaotic Aether Active — Blanks become Chaos", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = MtgGoldBright)
        Spacer(Modifier.width(8.dp))
        Icon(Icons.Default.FlashOn, null, tint = MtgGoldBright, modifier = Modifier.size(14.dp))
    }
}
