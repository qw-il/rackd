import SwiftData
import SwiftUI

@main
struct RackdApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ClothingItem.self, Outfit.self, OutfitPlan.self])
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            WardrobeView()
                .tabItem { Label("Wardrobe", systemImage: "hanger") }

            OutfitsView()
                .tabItem { Label("Outfits", systemImage: "square.stack.3d.up") }

            OutfitCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
        }
    }
}
