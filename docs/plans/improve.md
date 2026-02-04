# Building modern macOS menu bar apps in SwiftUI

**SwiftUI now provides native support for menu bar apps via `MenuBarExtra`**, eliminating the need for AppKit bridging in most cases. For macOS 14-15 (2024-2025), the recommended approach combines `.menuBarExtraStyle(.window)` for rich UI, SwiftUI materials for glass effects, and `UNUserNotificationCenter` for local notifications—all working seamlessly in LSUIElement agent apps without special entitlements. The key limitation remains that `MenuBarExtra` lacks programmatic show/hide control, requiring third-party packages like MenuBarExtraAccess for advanced functionality.

## Glass and vibrancy effects achieve native translucency

SwiftUI materials provide the frosted-glass aesthetic seen in apps like Raycast and Arc browser. Five material thickness levels exist, from `.ultraThinMaterial` (maximum translucency) through `.thickMaterial` (maximum contrast for text legibility).

```swift
struct GlassCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search...")
                .foregroundStyle(.secondary)
            
            ForEach(items) { item in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("⌘1")
                        .foregroundStyle(.quaternary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
```

**Vibrancy for text** requires using `.foregroundStyle()` with semantic styles—`.primary`, `.secondary`, `.tertiary`, and `.quaternary`. These automatically blend with the material background and adapt to light/dark mode. Critically, `.tertiary` and `.quaternary` are styles, not colors, so `.foregroundColor()` won't work.

For stronger behind-window blending (desktop showing through), bridge to `NSVisualEffectView`:

```swift
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
```

Use `.behindWindow` blending for maximum desktop translucency, `.withinWindow` for content-only blending. The **hybrid approach**—`NSVisualEffectView` as background with SwiftUI materials on controls—delivers the most authentic macOS glass appearance.

## MenuBarExtra patterns and known limitations

The `.menuBarExtraStyle(.window)` style enables full SwiftUI rendering with custom controls, while `.menu` provides standard dropdown menus but blocks the runloop while open and ignores `.onAppear`.

```swift
@main
struct MenuBarApp: App {
    @StateObject private var appState = AppState()
    @State private var isMenuInserted = true
    
    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuInserted) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("MyApp", systemImage: appState.statusIcon)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(isMenuInserted: $isMenuInserted)
        }
    }
}
```

**Sizing** works via `.frame()` on the root content view—**280-350pt width** is typical for utility apps. The window auto-resizes based on content, but animated size changes aren't supported natively.

**Keyboard navigation** uses `@FocusState` and `.keyboardShortcut()`:

```swift
struct MenuBarView: View {
    @FocusState private var searchFocused: Bool
    
    var body: some View {
        VStack {
            TextField("Search...", text: $searchText)
                .focused($searchFocused)
            
            Button("Refresh") { refresh() }
                .keyboardShortcut("r")
            
            SettingsLink { Text("Settings") }
                .keyboardShortcut(",")
        }
        .onAppear { searchFocused = true }
    }
}
```

For **programmatic popover control**, Apple provides no native API—use MenuBarExtraAccess:

```swift
import MenuBarExtraAccess

MenuBarExtra("App", systemImage: "star") {
    ContentView()
}
.menuBarExtraStyle(.window)
.menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
    // Direct NSStatusItem access if needed
}
```

For **smooth animated resizing**, FluidMenuBarExtra replaces the native implementation with proper transition support.

## Local notifications work identically in LSUIElement apps

Menu bar apps using `LSUIElement` have **no special notification requirements**—local notifications function without additional entitlements or configurations beyond the standard implementation.

Set the delegate early in `applicationWillFinishLaunching`:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermission()
        registerCategories()
    }
    
    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            print("Notifications permitted: \(granted)")
        }
    }
    
    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View Details",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: "ALERT_CATEGORY",
            actions: [viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Required for foreground delivery
        completionHandler([.banner, .sound, .list])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            handleNotificationTap(response.notification.request.content.userInfo)
        case "VIEW":
            handleViewAction()
        default: break
        }
        completionHandler()
    }
}
```

Schedule notifications with immediate or delayed triggers:

```swift
class NotificationManager {
    static let shared = NotificationManager()
    
    func sendNotification(title: String, body: String, delay: TimeInterval? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "ALERT_CATEGORY"
        
        let trigger = delay.map { 
            UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) 
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger  // nil = immediate
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
```

**Gotcha**: The permission dialog may appear behind other windows in LSUIElement apps. Call `NSApp.activate(ignoringOtherApps: true)` before requesting authorization to ensure visibility.

## Design patterns create native-feeling interactions

Custom hover effects define the macOS interaction feel. Use `.onHover` with **0.12-0.15s ease-out** animations:

```swift
struct MacOSHoverEffect: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}
```

**Typography hierarchy** for information-dense UIs: **13pt** body text, **11pt** captions, **10pt** metadata. Use monospaced digits for numbers that update:

```swift
struct DesignConstants {
    struct Typography {
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let micro = Font.system(size: 10)
        static let monoCaption = Font.system(size: 11, design: .monospaced)
    }
}
```

**SF Symbols** should use `.hierarchical` rendering for depth and `.symbolEffect(.bounce)` for state-change animations (macOS 14+):

```swift
Image(systemName: "folder.fill.badge.plus")
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(.blue)

Image(systemName: isFavorite ? "star.fill" : "star")
    .symbolEffect(.bounce, value: isFavorite)
    .onTapGesture { isFavorite.toggle() }
```

**Custom button styles** need subtle scale/opacity feedback:

```swift
struct MenuBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? 
                          Color.primary.opacity(0.1) : 
                          Color.primary.opacity(0.05))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

## Project structure and entitlements configuration

The recommended structure places local Swift packages in a `Packages/` directory:

```
MyMenuBarApp/
├── MyMenuBarApp.xcodeproj/
├── MyMenuBarApp/
│   ├── App/
│   │   └── MyMenuBarAppApp.swift
│   ├── Views/
│   ├── Services/
│   ├── Resources/
│   │   └── Assets.xcassets
│   ├── Info.plist
│   └── MyMenuBarApp.entitlements
├── Packages/
│   └── AppCore/
│       ├── Package.swift
│       └── Sources/AppCore/
└── Tests/
```

**Info.plist** for menu bar apps requires `LSUIElement`:

```xml
<key>LSUIElement</key>
<true/>
```

**Entitlements** for a sandboxed app with notifications:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- Only needed for push notifications -->
    <key>com.apple.developer.aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

**Local notifications require no entitlements**—only push notifications need `com.apple.developer.aps-environment`.

Create local packages via File → New → Package in Xcode, then drag into the project navigator. The `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
```

## Conclusion

Building modern macOS menu bar apps in SwiftUI (macOS 14-15) is now viable without AppKit bridging for most use cases. The key insight is that **`MenuBarExtra` with `.window` style** provides full SwiftUI rendering, though it lacks programmatic control (fixable with MenuBarExtraAccess). **Materials work natively for glass effects**, but strong behind-window blending still requires `NSVisualEffectView` bridging. **Notifications function identically** in LSUIElement apps with no special configuration—the critical step is setting the delegate in `applicationWillFinishLaunching`. For design, the macOS feel comes from **short animation durations (0.12-0.15s)**, **subtle hover opacity changes (0.05-0.06)**, and **semantic foreground styles** that adapt to materials automatically.
