package com.solomon.treachery.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val TreacheryColorScheme = darkColorScheme(
    primary = MtgGold,
    onPrimary = MtgBackground,
    primaryContainer = MtgGold,
    onPrimaryContainer = MtgBackground,
    secondary = MtgGoldBright,
    onSecondary = MtgBackground,
    background = MtgBackground,
    onBackground = MtgTextPrimary,
    surface = MtgSurface,
    onSurface = MtgTextPrimary,
    surfaceVariant = MtgCardElevated,
    onSurfaceVariant = MtgTextSecondary,
    error = MtgError,
    onError = MtgTextPrimary,
    outline = MtgDivider,
    outlineVariant = MtgDivider
)

@Composable
fun TreacheryTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = TreacheryColorScheme,
        typography = TreacheryTypography,
        content = content
    )
}
