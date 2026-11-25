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
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)   // makes stray paw swipes less likely to leave the app
            #if os(iOS)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }    // keep the screen awake
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            #endif
    }
}

#Preview {
    ContentView()
}
