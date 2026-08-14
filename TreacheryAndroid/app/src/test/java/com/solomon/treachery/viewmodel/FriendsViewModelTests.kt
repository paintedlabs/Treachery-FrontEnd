package com.solomon.treachery.viewmodel

import com.solomon.treachery.mocks.MockCloudFunctionsRepository
import com.solomon.treachery.mocks.MockFirestoreRepository
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.profile.FriendsViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FriendsViewModelTests {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var firestore: MockFirestoreRepository
    private lateinit var cloudFunctions: MockCloudFunctionsRepository
    private lateinit var vm: FriendsViewModel

    private val friend = TreacheryUser(id = "friend-1", displayName = "Ally")

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        firestore = MockFirestoreRepository()
        cloudFunctions = MockCloudFunctionsRepository()
        vm = FriendsViewModel(firestore, cloudFunctions)
    }

    @AfterEach
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `removeFriend calls cloud function and drops friend locally`() = runTest {
        firestore.friendsToReturn = mutableListOf(friend)
        vm.loadData("user-1")
        advanceUntilIdle()
        assertEquals(1, vm.friends.value.size)

        vm.removeFriend(friend)
        advanceUntilIdle()

        assertEquals(listOf("friend-1"), cloudFunctions.removeFriendCalls)
        assertTrue(vm.friends.value.isEmpty())
    }

    @Test
    fun `removeFriend failure sets error and keeps friend`() = runTest {
        firestore.friendsToReturn = mutableListOf(friend)
        vm.loadData("user-1")
        advanceUntilIdle()

        cloudFunctions.errorToThrow = RuntimeException("Server error")
        vm.removeFriend(friend)
        advanceUntilIdle()

        assertNotNull(vm.errorMessage.value)
        assertEquals(1, vm.friends.value.size)
    }
}
