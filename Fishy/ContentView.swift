import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var scene: PondScene = {
        let s = PondScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .statusBarHidden()
            .catProofed()
            #if os(iOS)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }    // keep the screen awake
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            #endif
    }
}

private extension View {
    /// Hide the home indicator and make stray paw swipes less likely to leave the app (iOS 16+).
    @ViewBuilder func catProofed() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            self.persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
}
