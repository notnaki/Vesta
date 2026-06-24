import Foundation

/// Caches Kitty-graphics protocol bytes so inline images survive detach/reattach.
/// `record(transmit:)` stores the raw transmit APC for an image id (last write
/// wins — a re-transmit replaces stale data). `place` appends a placement APC
/// referencing an id. `delete` drops an image and its placements. `replayBytes()`
/// concatenates, for each still-referenced image in ascending id order, its
/// transmit chunk followed by that image's placement chunks in arrival order.
public final class ImageCache {
    public struct Transmit: Equatable { public let id: UInt32; public let bytes: Data
        public init(id: UInt32, bytes: Data) { self.id = id; self.bytes = bytes } }
    public struct Placement: Equatable { public let imageID: UInt32; public let bytes: Data
        public init(imageID: UInt32, bytes: Data) { self.imageID = imageID; self.bytes = bytes } }
    private var transmits: [UInt32: Data] = [:]
    private var placements: [Placement] = []
    public init() {}
    public func record(transmit t: Transmit) { transmits[t.id] = t.bytes }   // last write wins
    public func place(_ p: Placement) { placements.append(p) }
    public func delete(imageID id: UInt32) {
        transmits[id] = nil
        placements.removeAll { $0.imageID == id }
    }
    public func replayBytes() -> Data {
        var out = Data()
        for id in transmits.keys.sorted() {           // ascending id, deterministic
            out.append(transmits[id]!)                 // transmit first
            for p in placements where p.imageID == id { out.append(p.bytes) }  // then its placements, arrival order
        }
        return out
    }
}

public func imageCacheSelfCheck() {
    let c = ImageCache()
    // Image 2 transmitted, then image 1 — replay must order by id, transmit before placement.
    c.record(transmit: .init(id: 2, bytes: Data([0x20])))
    c.record(transmit: .init(id: 1, bytes: Data([0x10])))
    c.place(.init(imageID: 1, bytes: Data([0xA1])))   // place image 1 once
    c.place(.init(imageID: 2, bytes: Data([0xB2])))   // place image 2
    c.place(.init(imageID: 1, bytes: Data([0xA1, 0x01])))  // second placement of image 1
    // Expected: img1 transmit, img1 placements (arrival order), img2 transmit, img2 placement.
    let expected = Data([0x10, 0xA1, 0xA1, 0x01, 0x20, 0xB2])
    assert(c.replayBytes() == expected, "replay = transmit-then-placements, ascending id")
    // Re-transmit of image 1 replaces its bytes (last write wins), placements kept.
    c.record(transmit: .init(id: 1, bytes: Data([0x11])))
    assert(c.replayBytes() == Data([0x11, 0xA1, 0xA1, 0x01, 0x20, 0xB2]), "re-transmit replaces image bytes")
    // Delete image 1 → its transmit and BOTH its placements vanish; image 2 remains.
    c.delete(imageID: 1)
    assert(c.replayBytes() == Data([0x20, 0xB2]), "delete removes image + its placements")
    // A placement referencing an unknown image id is dropped from replay (no transmit to anchor it).
    c.place(.init(imageID: 99, bytes: Data([0xFF])))
    assert(c.replayBytes() == Data([0x20, 0xB2]), "orphan placement excluded from replay")
    print("imageCacheSelfCheck ok")
}
