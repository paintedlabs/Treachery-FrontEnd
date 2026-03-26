package com.solomon.treachery.ui.theme

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun MtgTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    isSecure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    enabled: Boolean = true
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = {
            Text(placeholder, color = MtgTextSecondary)
        },
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        singleLine = true,
        visualTransformation = if (isSecure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = MtgTextPrimary,
            unfocusedTextColor = MtgTextPrimary,
            focusedContainerColor = MtgCardElevated,
            unfocusedContainerColor = MtgCardElevated,
            disabledContainerColor = MtgCardElevated.copy(alpha = 0.5f),
            focusedBorderColor = MtgGold,
            unfocusedBorderColor = MtgDivider,
            cursorColor = MtgGold
        ),
        shape = RoundedCornerShape(8.dp)
    )
}

@Composable
fun MtgPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.97f else 1f, label = "scale")

    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer(scaleX = scale, scaleY = scale),
        enabled = enabled && !isLoading,
        interactionSource = interactionSource,
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            disabledContainerColor = Color.Transparent
        ),
        contentPadding = PaddingValues(0.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    brush = if (enabled && !isLoading) {
                        Brush.verticalGradient(MtgGoldGradient)
                    } else {
                        Brush.verticalGradient(listOf(MtgGold.copy(alpha = 0.4f), MtgGold.copy(alpha = 0.4f)))
                    },
                    shape = RoundedCornerShape(10.dp)
                )
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center
        ) {
            if (isLoading) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = MtgBackground,
                        strokeWidth = 2.dp
                    )
                    Text(text, color = MtgBackground, fontWeight = FontWeight.SemiBold)
                }
            } else {
                Text(text, color = MtgBackground, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun MtgSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.97f else 1f, label = "scale")

    OutlinedButton(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer(scaleX = scale, scaleY = scale),
        enabled = enabled && !isLoading,
        interactionSource = interactionSource,
        shape = RoundedCornerShape(10.dp),
        border = ButtonDefaults.outlinedButtonBorder(enabled).copy(
            brush = Brush.linearGradient(listOf(MtgGold, MtgGold))
        ),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = if (isPressed) MtgGold.copy(alpha = 0.08f) else MtgGold.copy(alpha = 0.03f),
            contentColor = MtgGold
        ),
        contentPadding = PaddingValues(vertical = 14.dp)
    ) {
        if (isLoading) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = MtgGold,
                    strokeWidth = 2.dp
                )
                Text(text, fontWeight = FontWeight.Medium)
            }
        } else {
            Text(text, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
fun MtgCardFrame(
    modifier: Modifier = Modifier,
    borderColor: Color = MtgBorderAccent,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .shadow(4.dp, RoundedCornerShape(12.dp), ambientColor = Color.Black.copy(alpha = 0.25f))
            .clip(RoundedCornerShape(12.dp))
            .background(MtgSurface)
            .border(1.5.dp, borderColor, RoundedCornerShape(12.dp))
    ) {
        content()
    }
}

@Composable
fun OrnateDivider(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        HorizontalDivider(modifier = Modifier.weight(1f), color = MtgDivider)
        Text(
            "\u25C6",
            fontSize = 8.sp,
            color = MtgGold
        )
        HorizontalDivider(modifier = Modifier.weight(1f), color = MtgDivider)
    }
}

@Composable
fun MtgSectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        text = title.uppercase(),
        modifier = modifier,
        style = MaterialTheme.typography.labelSmall,
        letterSpacing = 1.5.sp,
        color = MtgGold
    )
}

@Composable
fun MtgErrorBanner(message: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Default.Warning,
            contentDescription = null,
            tint = MtgError,
            modifier = Modifier.size(14.dp)
        )
        Text(
            message,
            color = MtgError,
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
fun MtgGoldShimmerText(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: Float = 42f
) {
    Text(
        text = text,
        modifier = modifier,
        style = TextStyle(
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.Bold,
            fontSize = fontSize.sp,
            brush = Brush.linearGradient(
                colors = MtgGoldShimmerColors,
                start = Offset(0f, 0f),
                end = Offset(300f, 300f)
            )
        )
    )
}

@Composable
fun MtgRadialBackground(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MtgBackground)
            .background(
                brush = Brush.radialGradient(
                    colors = listOf(
                        MtgRadialCenter.copy(alpha = 0.8f),
                        MtgBackground
                    ),
                    radius = 500f
                )
            )
    )
}

@Composable
fun MtgStatBox(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
    color: Color = MtgTextPrimary
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(
                Brush.verticalGradient(
                    listOf(color.copy(alpha = 0.08f), Color.Transparent)
                )
            )
            .background(MtgCardElevated)
            .border(1.dp, color.copy(alpha = 0.2f), RoundedCornerShape(8.dp))
            .padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            value,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Text(
            label,
            fontSize = 10.sp,
            color = MtgTextSecondary
        )
    }
}
