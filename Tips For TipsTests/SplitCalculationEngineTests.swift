import XCTest
@testable import Tips_For_Tips

final class SplitCalculationEngineTests: XCTestCase {
    private let engine = SplitCalculationEngine()

    func testEqualSplitThreeWayPreservesRemainderCent() throws {
        let session = makeSession(mode: .equal, subtotal: 100, total: 100, participants: people(3))
        let result = try engine.calculate(session: session)
        XCTAssertEqual(result.roundedCollectedTotal, 100)
        XCTAssertEqual(result.participantResults.map(\.finalAmount).sorted(), [Decimal(string: "33.33")!, Decimal(string: "33.33")!, Decimal(string: "33.34")!])
    }

    func testCustomAmountRejectsUnderallocatedSubtotal() {
        var participants = people(2)
        participants[0].customAmount = 40
        participants[1].customAmount = 30
        let session = makeSession(mode: .customAmount, subtotal: 100, tax: 8, tip: 20, total: 128, participants: participants)
        XCTAssertThrowsError(try engine.calculate(session: session))
    }

    func testPercentageSplitAllocatesTaxAndTipProportionally() throws {
        var participants = people(2)
        participants[0].percentage = 75
        participants[1].percentage = 25
        let session = makeSession(mode: .percentage, subtotal: 100, tax: 10, tip: 20, total: 130, participants: participants)
        let result = try engine.calculate(session: session)
        XCTAssertEqual(result.participantResults[0].taxAmount, 7.50)
        XCTAssertEqual(result.participantResults[1].tipAmount, 5.00)
        XCTAssertEqual(result.roundedCollectedTotal, 130)
    }

    func testItemizedSharedItemAllocatesFullPrice() throws {
        let participants = people(3)
        let item = SplitItem(name: "Nachos", price: 10, assignments: participants.map { SplitItemAssignment(participantID: $0.id, share: Decimal(1) / Decimal(3)) }, sharingRule: .sharedBySelected)
        let session = makeSession(mode: .itemized, subtotal: 10, total: 10, participants: participants, items: [item])
        let result = try engine.calculate(session: session)
        XCTAssertEqual(result.roundedCollectedTotal, 10)
        XCTAssertEqual(result.participantResults.reduce(Decimal(0)) { $0 + $1.baseAmount }, 10)
    }

    func testRoundUpRuleDisclosesExtraCollected() throws {
        let session = makeSession(mode: .equal, subtotal: Decimal(string: "10.10")!, total: Decimal(string: "10.10")!, participants: people(2), rounding: .roundUpToDollar)
        let result = try engine.calculate(session: session)
        XCTAssertEqual(result.roundedCollectedTotal, 12)
        XCTAssertEqual(result.roundingDifference, Decimal(string: "1.90")!)
    }

    private func people(_ count: Int) -> [SplitParticipant] { (1...count).map { SplitParticipant(name: "Person \($0)") } }
    private func makeSession(mode: SplitMode, subtotal: Decimal, tax: Decimal = 0, tip: Decimal = 0, total: Decimal, participants: [SplitParticipant], items: [SplitItem] = [], rounding: SplitRoundingRule = .exactCents) -> SplitSession {
        SplitSession(id: UUID(), name: "Test", mode: mode, currencyCode: "USD", subtotal: subtotal, tax: tax, tipAmount: tip, total: total, participants: participants, items: items, taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: rounding, sourceCalculationID: nil, receiptID: nil, createdAt: Date(), updatedAt: Date())
    }
}
