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
            .catProofed()
            #if os(iOS) || os(tvOS)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }    // keep the screen awake / no screensaver
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            #endif
    }
}

private extension View {
    /// iPad only: hide the status bar and home indicator, and make stray paw swipes less likely to leave the app.
    @ViewBuilder func catProofed() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
        } else {
            self.statusBarHidden()
        }
        #else
        self
        #endif
    }
}

#Preview {
    ContentView()
}
