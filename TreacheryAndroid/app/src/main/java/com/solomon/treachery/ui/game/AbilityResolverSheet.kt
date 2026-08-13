package com.solomon.treachery.ui.game

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*

// Resolver UI for the three callable-backed traitor abilities. Mirrors the
// iOS ability sheets (Home/Abilities/) and web AbilityResolver.tsx.
@Composable
fun AbilityResolverSheet(
    ability: ExecutableAbility,
    viewModel: GameBoardViewModel,
    onDismiss: () -> Unit
) {
    val players by viewModel.players.collectAsState()
    val isPending by viewModel.isPending.collectAsState()

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Scaffold(
            containerColor = MtgBackground,
            topBar = {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = {
                        // Wearer of Masks skip explicitly declines server-side; the
                        // server's decline path never sets ability_resolved.
                        if (ability == ExecutableAbility.WEARER_OF_MASKS) {
                            viewModel.resolveWearerOfMasks(null)
                        }
                        onDismiss()
                    }) { Text("Skip", color = MtgTextSecondary) }
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                when (ability) {
                    ExecutableAbility.METAMORPH -> MetamorphContent(
                        viewModel = viewModel,
                        players = players,
                        isPending = isPending,
                        onDismiss = onDismiss
                    )
                    ExecutableAbility.PUPPET_MASTER -> PuppetMasterContent(
                        viewModel = viewModel,
                        players = players,
                        isPending = isPending,
                        onDismiss = onDismiss
                    )
                    ExecutableAbility.WEARER_OF_MASKS -> WearerOfMasksContent(
                        viewModel = viewModel,
                        isPending = isPending,
                        onDismiss = onDismiss
                    )
                }
            }
        }
    }
}

// ── Shared pieces ──

@Composable
private fun AbilityHeader(icon: @Composable () -> Unit, title: String, reminder: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        icon()
        Text(title, fontSize = 22.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif, color = MtgTextPrimary)
        Text(reminder, fontSize = 12.sp, color = MtgTextSecondary, textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 16.dp))
    }
}

private fun selectableRowModifier(isSelected: Boolean): Modifier = Modifier
    .fillMaxWidth()
    .clip(RoundedCornerShape(8.dp))
    .background(if (isSelected) MtgTraitor.copy(alpha = 0.15f) else MtgSurface)
    .border(
        if (isSelected) 2.dp else 1.dp,
        if (isSelected) MtgTraitor else MtgDivider,
        RoundedCornerShape(8.dp)
    )

// ── Metamorph ──

@Composable
private fun MetamorphContent(
    viewModel: GameBoardViewModel,
    players: List<Player>,
    isPending: Boolean,
    onDismiss: () -> Unit
) {
    // Server requires an eliminated non-Leader target that still has a card
    val eliminated = players.filter {
        it.isEliminated && it.role != Role.LEADER &&
            it.userId != viewModel.currentUserId && it.identityCardId != null
    }
    var selectedPlayerId by remember { mutableStateOf<String?>(null) }
    var showConfirmation by remember { mutableStateOf(false) }

    if (showConfirmation) {
        val target = eliminated.find { it.id == selectedPlayerId }
        val card = target?.let { viewModel.identityCard(it) }
        AlertDialog(
            onDismissRequest = { showConfirmation = false },
            title = { Text("Steal Identity", color = MtgTextPrimary) },
            text = {
                Text(
                    "Replace The Metamorph with ${card?.name ?: "the stolen card"}? Your identity card will be removed from the game. This cannot be undone.",
                    color = MtgTextSecondary
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showConfirmation = false
                    selectedPlayerId?.let { viewModel.resolveMetamorph(it) }
                    onDismiss()
                }) { Text("Steal Identity", color = MtgGold) }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmation = false }) { Text("Cancel", color = MtgTextSecondary) }
            },
            containerColor = MtgSurface
        )
    }

    AbilityHeader(
        icon = { Icon(Icons.Default.SwapHoriz, null, tint = MtgTraitor, modifier = Modifier.size(40.dp)) },
        title = "The Metamorph",
        reminder = "As an opponent loses the game, you may remove The Metamorph and gain control of that player's identity card. Turn it face down if it isn't a Leader."
    )

    if (eliminated.isEmpty()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MtgSurface)
                .border(1.dp, MtgDivider, RoundedCornerShape(12.dp))
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(Icons.Default.PersonOff, null, tint = MtgTextSecondary, modifier = Modifier.size(32.dp))
            Text("No eliminated opponents yet", fontWeight = FontWeight.Medium, color = MtgTextPrimary)
            Text(
                "This ability triggers when an opponent loses the game this turn. Keep this in mind for the rest of the turn.",
                fontSize = 12.sp, color = MtgTextSecondary, textAlign = TextAlign.Center
            )
        }
    } else {
        Text("Steal an Identity", fontWeight = FontWeight.Bold, color = MtgGold)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            eliminated.forEach { player ->
                val isSelected = selectedPlayerId == player.id
                val card = viewModel.identityCard(player)
                Row(
                    modifier = selectableRowModifier(isSelected)
                        .clickable { selectedPlayerId = if (isSelected) null else player.id }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(player.displayName, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary,
                            textDecoration = TextDecoration.LineThrough)
                        if (card != null) {
                            val cardRoleColor = card.roleEnum?.roleColor ?: MtgTextSecondary
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Box(Modifier.size(8.dp).clip(CircleShape).background(cardRoleColor))
                                Text(card.name, fontSize = 12.sp, color = cardRoleColor)
                            }
                            Text(card.abilityText, fontSize = 11.sp, color = MtgTextSecondary, maxLines = 2)
                        }
                    }
                    if (isSelected) {
                        Icon(Icons.Default.CheckCircle, null, tint = MtgGold, modifier = Modifier.size(22.dp))
                    }
                }
            }
        }

        if (selectedPlayerId != null) {
            MtgPrimaryButton(
                text = "Steal Identity",
                onClick = { showConfirmation = true },
                enabled = !isPending
            )
        }
    }
    MtgSecondaryButton(text = "Decline", onClick = onDismiss, enabled = !isPending)
}

// ── Puppet Master ──

@Composable
private fun PuppetMasterContent(
    viewModel: GameBoardViewModel,
    players: List<Player>,
    isPending: Boolean,
    onDismiss: () -> Unit
) {
    // Server validates targets are other, non-eliminated players. Card-less
    // players are excluded too: swapping with one would drop the giver from
    // the assignment map and the server's permutation check rejects that.
    // (Unreachable today — only eliminated players get their card nulled —
    // but the filter keeps an impossible payload impossible.)
    val swappable = players.filter {
        !it.isEliminated && it.userId != viewModel.currentUserId && it.identityCardId != null
    }

    // Local swap state: playerId -> cardId
    val assignments = remember {
        mutableStateMapOf<String, String>().apply {
            swappable.forEach { p -> p.identityCardId?.let { put(p.id, it) } }
        }
    }
    var firstSelection by remember { mutableStateOf<String?>(null) }
    var showConfirmation by remember { mutableStateOf(false) }

    val swapCount = swappable.count { assignments[it.id] != it.identityCardId }

    if (showConfirmation) {
        AlertDialog(
            onDismissRequest = { showConfirmation = false },
            title = { Text("Confirm Redistribution", color = MtgTextPrimary) },
            text = {
                Text(
                    "$swapCount card${if (swapCount == 1) "" else "s"} will be redistributed. Non-Leader cards will be turned face down.",
                    color = MtgTextSecondary
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showConfirmation = false
                    viewModel.resolvePuppetMaster(assignments.toMap())
                    onDismiss()
                }) { Text("Redistribute Cards", color = MtgGold) }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmation = false }) { Text("Cancel", color = MtgTextSecondary) }
            },
            containerColor = MtgSurface
        )
    }

    AbilityHeader(
        icon = { Icon(Icons.Default.Repeat, null, tint = MtgTraitor, modifier = Modifier.size(40.dp)) },
        title = "The Puppet Master",
        reminder = "Redistribute control of any number of other identity cards. Each player must control one identity card. Non-Leader cards are turned face down."
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MtgCardElevated)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(Icons.Default.TouchApp, null, tint = MtgGold, modifier = Modifier.size(16.dp))
        Text(
            if (firstSelection == null) "Tap a player's card to select it for swapping"
            else "Now tap another player to swap with",
            fontSize = 12.sp, color = MtgTextPrimary
        )
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        swappable.forEach { player ->
            val wasSwapped = assignments[player.id] != player.identityCardId
            val isFirstSelected = firstSelection == player.id
            Row(
                modifier = selectableRowModifier(isFirstSelected)
                    .clickable {
                        val first = firstSelection
                        if (first == null) {
                            firstSelection = player.id
                        } else if (first == player.id) {
                            firstSelection = null
                        } else {
                            // Swap the two players' assigned cards
                            val cardA = assignments[first]
                            val cardB = assignments[player.id]
                            if (cardB != null) assignments[first] = cardB else assignments.remove(first)
                            if (cardA != null) assignments[player.id] = cardA else assignments.remove(player.id)
                            firstSelection = null
                        }
                    }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(player.displayName, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary)
                        if (wasSwapped) {
                            Text("SWAPPED", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = MtgBackground,
                                modifier = Modifier.background(MtgTraitor, RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 1.dp))
                        }
                    }
                    // Never reveal which identity a player holds — names only
                    Text("Identity hidden", fontSize = 12.sp, color = MtgTextSecondary)
                }
                Icon(
                    Icons.Default.SwapHoriz, null,
                    tint = if (isFirstSelected) MtgGold else MtgTextSecondary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }

    if (swapCount > 0) {
        MtgPrimaryButton(
            text = "Confirm Redistribution",
            onClick = { showConfirmation = true },
            enabled = !isPending
        )
        MtgSecondaryButton(
            text = "Undo All Swaps",
            onClick = {
                assignments.clear()
                swappable.forEach { p -> p.identityCardId?.let { assignments[p.id] = it } }
                firstSelection = null
            },
            enabled = !isPending
        )
    }
    MtgSecondaryButton(text = "Decline", onClick = onDismiss, enabled = !isPending)
}

// ── Wearer of Masks ──

@Composable
private fun WearerOfMasksContent(
    viewModel: GameBoardViewModel,
    isPending: Boolean,
    onDismiss: () -> Unit
) {
    var xValue by remember { mutableIntStateOf(3) }
    var revealedCards by remember { mutableStateOf<List<IdentityCard>>(emptyList()) }
    var hasRevealed by remember { mutableStateOf(false) }
    var selectedCardId by remember { mutableStateOf<String?>(null) }

    AbilityHeader(
        icon = { Icon(Icons.Default.TheaterComedy, null, tint = MtgTraitor, modifier = Modifier.size(40.dp)) },
        title = "The Wearer of Masks",
        reminder = "Reveal up to X non-Leader identity cards at random from outside the game. You may choose one to become a copy of, except it's a Traitor."
    )

    if (!hasRevealed) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MtgSurface)
                .border(1.dp, MtgDivider, RoundedCornerShape(12.dp))
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("How much mana did you pay for X?", color = MtgTextPrimary)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                IconButton(onClick = { if (xValue > 1) xValue -= 1 }) {
                    Icon(Icons.Default.RemoveCircle, "Decrease X", tint = MtgAssassin, modifier = Modifier.size(32.dp))
                }
                Text("$xValue", fontSize = 48.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Serif,
                    color = MtgGold, modifier = Modifier.widthIn(min = 60.dp), textAlign = TextAlign.Center)
                IconButton(onClick = { xValue += 1 }) {
                    Icon(Icons.Default.AddCircle, "Increase X", tint = MtgSuccess, modifier = Modifier.size(32.dp))
                }
            }
        }
        MtgPrimaryButton(
            text = "Reveal Cards",
            onClick = {
                val available = viewModel.cardsOutsideGame()
                revealedCards = available.shuffled().take(minOf(xValue, available.size))
                hasRevealed = true
            },
            enabled = !isPending
        )
    } else {
        Text("Choose an Identity", fontWeight = FontWeight.Bold, color = MtgGold)
        if (revealedCards.isEmpty()) {
            Text("No eligible cards outside the game.", color = MtgTextSecondary)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                revealedCards.forEach { card ->
                    val isSelected = selectedCardId == card.id
                    val cardRoleColor = card.roleEnum?.roleColor ?: MtgTextSecondary
                    Column(
                        modifier = selectableRowModifier(isSelected)
                            .clickable { selectedCardId = if (isSelected) null else card.id }
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Box(Modifier.size(10.dp).clip(CircleShape).background(cardRoleColor))
                            Text(card.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MtgTextPrimary)
                            Spacer(Modifier.weight(1f))
                            Text(card.roleEnum?.displayName ?: card.role, fontSize = 12.sp, color = cardRoleColor)
                            if (isSelected) {
                                Icon(Icons.Default.CheckCircle, null, tint = MtgGold, modifier = Modifier.size(18.dp))
                            }
                        }
                        Text(card.abilityText, fontSize = 12.sp, color = MtgTextSecondary, maxLines = 3)
                    }
                }
            }
        }

        if (selectedCardId != null) {
            MtgPrimaryButton(
                text = "Become This Identity",
                onClick = {
                    selectedCardId?.let { viewModel.resolveWearerOfMasks(it) }
                    onDismiss()
                },
                enabled = !isPending
            )
        }
    }
    MtgSecondaryButton(
        text = "Decline",
        onClick = {
            // Explicit decline — the server's Skip path never sets ability_resolved
            viewModel.resolveWearerOfMasks(null)
            onDismiss()
        },
        enabled = !isPending
    )
}
