import SwiftUI
import SwiftData

@main
struct KitchenInventoryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Grocery.self, Supermarket.self])
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            ShoppingListView()
                .tabItem { Label("采购清单", systemImage: "cart") }
            InventoryView()
                .tabItem { Label("智能库存", systemImage: "refrigerator") }
        }
        .onAppear { GroceryActions.seedDefaultStaplesIfNeeded(in: context) }
    }
}
