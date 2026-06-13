import SwiftUI

// NOTE: this is the Xcode app target's entry point (Task 12 / XcodeGen). It is
// NOT a SwiftPM target — `swift build` does not compile it. Task 8 builds out
// the real 4-tab shell.
@main
struct FinchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("finch — Phase 1.0 bootstrap")
        }
    }
}
