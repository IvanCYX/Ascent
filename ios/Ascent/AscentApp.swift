import SwiftUI
import AscentUI

@main
struct AscentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AscentRoot(model: model)
        }
    }
}
