import SwiftUI
import Combine

/// A protocol representing a modular widget in NotchPilot.
@MainActor
public protocol SherpaModule: AnyObject, Identifiable {
    associatedtype View: SwiftUI.View
    
    var id: String { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    
    func start()
    func stop()
    
    var view: View { get }
}

public extension SherpaModule {
    var isEnabled: Bool {
        get {
            let enabledStates = UserDefaults.standard.dictionary(forKey: "sherpa.modules.enabled") as? [String: Bool] ?? [:]
            return enabledStates[id] ?? false
        }
        set {
            SherpaModuleRegistry.shared.setEnabled(newValue, for: self)
        }
    }
}

/// A registry that manages registered Sherpa modules and their enabled state.
@MainActor
public final class SherpaModuleRegistry: ObservableObject {
    public static let shared = SherpaModuleRegistry()
    
    @Published public private(set) var modules: [any SherpaModule] = []
    
    private let userDefaultsKey = "sherpa.modules.enabled"
    
    private init() {}
    
    public func register(_ module: any SherpaModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        
        let enabledStates = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Bool] ?? [:]
        let savedState = enabledStates[module.id] ?? false
        
        // If the module's initial state doesn't match the saved state, sync it.
        // If using the default extension, this setter call is a no-op due to oldValue check in setEnabled.
        if module.isEnabled != savedState {
            module.isEnabled = savedState
        }
        
        if savedState {
            module.start()
        } else {
            module.stop()
        }
        
        modules.append(module)
    }
    
    public func unregister(_ module: any SherpaModule) {
        guard let index = modules.firstIndex(where: { $0.id == module.id }) else { return }
        let removedModule = modules.remove(at: index)
        removedModule.stop()
    }
    
    public func setEnabled(_ isEnabled: Bool, for module: any SherpaModule) {
        var enabledStates = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Bool] ?? [:]
        let oldValue = enabledStates[module.id] ?? false
        
        guard oldValue != isEnabled else { return }
        
        enabledStates[module.id] = isEnabled
        UserDefaults.standard.set(enabledStates, forKey: userDefaultsKey)
        
        if isEnabled {
            module.start()
        } else {
            module.stop()
        }
        
        // Synchronize the conforms-to property if it was overridden with a stored property
        if module.isEnabled != isEnabled {
            module.isEnabled = isEnabled
        }
        
        // Trigger SwiftUI publisher updates
        objectWillChange.send()
    }
}
