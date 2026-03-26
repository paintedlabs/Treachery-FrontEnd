import Testing
@testable import Treachery_iOS

struct PlaneDatabaseTests {

    @Test func loadsCards() {
        #expect(!PlaneDatabase.shared.allCards.isEmpty)
    }

    @Test func allPlanesExcludesPhenomena() {
        let planes = PlaneDatabase.shared.allPlanes
        #expect(planes.allSatisfy { !$0.isPhenomenon })
    }

    @Test func allCardsIncludesPhenomena() {
        let all = PlaneDatabase.shared.allCards
        let phenomena = all.filter(\.isPhenomenon)
        let planes = all.filter { !$0.isPhenomenon }
        #expect(planes.count + phenomena.count == all.count)
        #expect(!phenomena.isEmpty) // Should have at least some phenomena
    }

    @Test func lookupById() {
        let db = PlaneDatabase.shared
        guard let first = db.allCards.first else {
            Issue.record("No cards loaded")
            return
        }
        let found = db.plane(withId: first.id)
        #expect(found?.id == first.id)
    }

    @Test func returnsNilForMissingId() {
        #expect(PlaneDatabase.shared.plane(withId: "nonexistent") == nil)
    }

    @Test func randomPlaneExcludesUsedIds() {
        let db = PlaneDatabase.shared
        let allIds = Set(db.allPlanes.map(\.id))
        let plane = db.randomPlane(excluding: [])
        #expect(plane != nil)

        // Exclude all but one
        guard let keepId = db.allPlanes.first?.id else { return }
        let excludeAll = allIds.subtracting([keepId])
        let result = db.randomPlane(excluding: excludeAll)
        #expect(result?.id == keepId)
    }

    @Test func randomPlaneReturnsNilWhenAllExcluded() {
        let db = PlaneDatabase.shared
        let allIds = Set(db.allPlanes.map(\.id))
        let result = db.randomPlane(excluding: allIds)
        #expect(result == nil)
    }

    @Test func allCardsHaveUniqueIds() {
        let ids = PlaneDatabase.shared.allCards.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
