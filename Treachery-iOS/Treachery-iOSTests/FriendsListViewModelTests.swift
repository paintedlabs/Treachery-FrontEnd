import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct FriendsListViewModelTests {

    // MARK: - Helpers

    private func makeFriend(id: String = "f1", displayName: String = "Friend") -> TreacheryUser {
        TreacheryUser(
            id: id, displayName: displayName, email: nil, phoneNumber: nil,
            friendIds: [], createdAt: Date()
        )
    }

    // MARK: - removeFriend

    @Test func removeFriendCallsCloudFunctionAndRemovesLocally() async {
        let mockFS = MockFirestoreManager()
        let mockCF = MockCloudFunctions()
        let friend = makeFriend()
        mockFS.friendsToReturn = [friend]

        let vm = FriendsListViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        await vm.loadData(userId: "u1")
        #expect(vm.friends.count == 1)

        await vm.removeFriend(friend)
        #expect(mockCF.removeFriendCalls == ["f1"])
        #expect(vm.friends.isEmpty)
    }

    @Test func removeFriendSetsErrorAndKeepsFriendOnFailure() async {
        let mockFS = MockFirestoreManager()
        let mockCF = MockCloudFunctions()
        let friend = makeFriend()
        mockFS.friendsToReturn = [friend]

        let vm = FriendsListViewModel(firestoreManager: mockFS, cloudFunctions: mockCF)
        await vm.loadData(userId: "u1")

        mockCF.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "remove failed"])
        await vm.removeFriend(friend)
        #expect(vm.errorMessage == "remove failed")
        #expect(vm.friends.count == 1)
    }
}
