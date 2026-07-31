import SwiftUI

/// Phase 6.3 — the full-screen cover shown when `BiometricGate.isLocked`. Hides
/// the financial content and offers an Unlock button (auto-prompts on appear).
struct LockView: View {
    @EnvironmentObject private var gate: BiometricGate

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("finch is locked").font(.title3).fontWeight(.semibold)
                Button {
                    Task { await gate.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await gate.unlock() }   // auto-prompt as soon as the cover appears
    }
}
