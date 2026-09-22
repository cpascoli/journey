import XCTest

@testable import Journey

final class MediaOrderTests: XCTestCase {
    private let ids = ["a", "b", "c", "d"]

    func testMovingAnItemLaterPutsItBeforeTheTarget() {
        XCTAssertEqual(MediaOrder.moving("a", before: "c", in: ids), ["b", "a", "c", "d"])
    }

    func testMovingAnItemEarlierPutsItBeforeTheTarget() {
        XCTAssertEqual(MediaOrder.moving("d", before: "b", in: ids), ["a", "d", "b", "c"])
    }

    func testMovingOntoTheFirstItemMakesItFirst() {
        XCTAssertEqual(MediaOrder.moving("c", before: "a", in: ids), ["c", "a", "b", "d"])
    }

    /// A drop that means nothing must not disturb the order.
    func testAMoveOntoItselfChangesNothing() {
        XCTAssertEqual(MediaOrder.moving("b", before: "b", in: ids), ids)
    }

    /// An id the entry no longer holds must never drop an item or duplicate one.
    func testUnknownIdsLeaveTheOrderAlone() {
        XCTAssertEqual(MediaOrder.moving("z", before: "b", in: ids), ids)
        XCTAssertEqual(MediaOrder.moving("b", before: "z", in: ids), ids)
    }

    func testEveryMoveKeepsExactlyTheSameItems() {
        for from in ids {
            for to in ids {
                let result = MediaOrder.moving(from, before: to, in: ids)
                XCTAssertEqual(result.sorted(), ids.sorted(), "\(from) before \(to) changed the set")
                XCTAssertEqual(Set(result).count, result.count, "\(from) before \(to) duplicated an item")
            }
        }
    }

    func testMovingToTheEnd() {
        XCTAssertEqual(MediaOrder.movingToEnd("a", in: ids), ["b", "c", "d", "a"])
        // Already last, so nothing to do.
        XCTAssertEqual(MediaOrder.movingToEnd("d", in: ids), ids)
        XCTAssertEqual(MediaOrder.movingToEnd("z", in: ids), ids)
    }

    /// Insert-before alone cannot make an item last, which is why
    /// `movingToEnd` exists rather than being a special case of `moving`.
    func testAnyOrderIsReachable() {
        var order = ids
        order = MediaOrder.moving("d", before: "a", in: order)
        order = MediaOrder.movingToEnd("b", in: order)
        XCTAssertEqual(order, ["d", "a", "c", "b"])
    }

    func testASingleItemIsAlwaysAlreadyInOrder() {
        XCTAssertEqual(MediaOrder.moving("a", before: "a", in: ["a"]), ["a"])
        XCTAssertEqual(MediaOrder.movingToEnd("a", in: ["a"]), ["a"])
    }
}
