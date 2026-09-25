import Foundation
import SwiftUI
import Testing
@testable import Onyx

/// Precision A3 (Q6): one size per column. `18.75` printed smaller than `20`
/// on the same card because the load field shrank on its own whenever a
/// string crossed a floor that was an ESTIMATE of the string. The field no
/// longer shrinks, so the floor has to be the string's real width.
@MainActor
@Suite("Set row type")
struct SetRowTypeTests {

    private func size(_ text: String, _ type: DynamicTypeSize) -> CGSize {
        (text as NSString).size(withAttributes: [.font: SetColumn.numeralFont(type)])
    }

    @Test("\"20\" and \"18.75\" share one font and one line height at every non-accessibility size")
    func oneFaceOneHeight() {
        for type in DynamicTypeSize.allCases where !type.isAccessibilitySize {
            let font = SetColumn.numeralFont(type)
            #expect(size("20", type).height == size("18.75", type).height, "\(type)")
            #expect(font.pointSize == UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(type))
            ).pointSize, "the value face IS body at \(type)")
        }
    }

    @Test("the load floor holds 188.75 whole at every size, and grows with the type")
    func floorFitsTheWidestLoad() {
        var previous: CGFloat = 0
        for type in DynamicTypeSize.allCases {
            let floor = SetColumn.weightFloor(type)
            #expect(floor >= size("188.75", type).width, "\(type)")
            #expect(floor >= previous, "\(type) is not narrower than the size below it")
            previous = floor
        }
        // Two glyphs never need more than the header's rep column short of
        // the accessibility range, so the header and the row still agree.
        for type in DynamicTypeSize.allCases where !type.isAccessibilitySize {
            #expect(SetColumn.repsFloor(type) == SetColumn.repsField, "\(type)")
        }
    }
}
