import Foundation

protocol PlaneLookupProviding {
    var allCards: [PlaneCard] { get }
    var allPlanes: [PlaneCard] { get }
    func plane(withId id: String) -> PlaneCard?
    func randomPlane(excluding usedIds: Set<String>) -> PlaneCard?
}
