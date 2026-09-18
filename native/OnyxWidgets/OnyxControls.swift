import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (D3): the three things you do without opening the app first.
///
/// A bundle of its own because a `WidgetBundle` body holds ten entries and the
/// main one is at nine. `OnyxWidgets.body` includes it as `OnyxControls().body`.
struct OnyxControls: WidgetBundle {
    var body: some Widget {
        OnyxStartSessionControl()
        OnyxAddWaterControl()
        OnyxLogStressControl()
    }
}

/// `kind:` strings are load-bearing here too — a control that loses its kind
/// leaves Control Center.
struct OnyxStartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OnyxControlStartSession") {
            ControlWidgetButton(action: OpenOnyxIntent(path: "/workout")) {
                Label("Start session", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Start session")
        .description("Opens today's session in Onyx.")
    }
}

struct OnyxAddWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OnyxControlAddWater") {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("+250 ml", systemImage: "drop.fill")
            }
        }
        .displayName("Add water")
        .description("Adds a 250 ml glass to today without opening Onyx.")
    }
}

struct OnyxLogStressControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // ponytail: `/day` lands on the Pulse tab; the router drops `section`
        // today (RootView.tab(for:)). Thread it through when Body grows a
        // section route and this opens the stress sheet directly.
        StaticControlConfiguration(kind: "OnyxControlLogStress") {
            ControlWidgetButton(action: OpenOnyxIntent(path: "/day?section=stress")) {
                Label("Log stress", systemImage: "brain.head.profile")
            }
        }
        .displayName("Log stress")
        .description("Opens Onyx on today's Pulse page to log stress.")
    }
}
