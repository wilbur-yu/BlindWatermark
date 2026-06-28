import SwiftUI

@main
struct BlindWatermarkApp: App {
    var body: some Scene {
        Window("盲水印", id: "main") {
            ContentView()
                .frame(minWidth: 800, idealWidth: 880, maxWidth: .infinity,
                       minHeight: 560, idealHeight: 640, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
    }
}
