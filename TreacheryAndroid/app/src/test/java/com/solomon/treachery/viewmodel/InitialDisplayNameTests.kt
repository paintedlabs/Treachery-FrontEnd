package com.solomon.treachery.viewmodel

import com.solomon.treachery.ui.auth.initialDisplayName
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * The name a new profile starts with. It is public (users/{uid} is readable
 * by every signed-in user), so it must never be built from the email or
 * phone number; Firebase Auth's display name is the only input besides
 * whether the account is a guest.
 */
class InitialDisplayNameTests {

    @Test
    fun `guest starts as Guest`() {
        assertEquals("Guest", initialDisplayName(authDisplayName = null, isAnonymous = true))
    }

    @Test
    fun `email or phone account starts as Player`() {
        // Email and phone sign-ups have no Auth display name.
        assertEquals("Player", initialDisplayName(authDisplayName = null, isAnonymous = false))
    }

    @Test
    fun `auth display name wins when present`() {
        assertEquals("Ada", initialDisplayName(authDisplayName = "Ada", isAnonymous = false))
        assertEquals("Ada", initialDisplayName(authDisplayName = "  Ada ", isAnonymous = true))
    }

    @Test
    fun `blank auth display name is ignored`() {
        assertEquals("Player", initialDisplayName(authDisplayName = "", isAnonymous = false))
        assertEquals("Guest", initialDisplayName(authDisplayName = "   ", isAnonymous = true))
    }
}
