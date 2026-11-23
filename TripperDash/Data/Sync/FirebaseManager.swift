import Foundation

@Observable
public final class FirebaseManager: @unchecked Sendable {
    public static let shared = FirebaseManager()
    
    public var isConfigured: Bool = false
    public var isSignedIn: Bool = false
    public var userEmail: String? = nil
    public var lastSyncTime: Date? = nil
    public var isSyncing: Bool = false
    public var syncStatusMessage: String = "Not connected"
    
    private init() {
        checkConfiguration()
    }
    
    public func checkConfiguration() {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let projectId = plist["PROJECT_ID"] as? String,
           !projectId.isEmpty && projectId != "YOUR_PROJECT_ID" {
            isConfigured = true
            syncStatusMessage = "Ready to sync with \(projectId)"
        } else {
            isConfigured = false
            syncStatusMessage = "Add GoogleService-Info.plist to enable cloud sync"
        }
    }
    
    // MARK: - Auth & Cloud Sync Stubs (Pre-wired for Firebase SDK)
    public func signIn(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // When Firebase SDK is added via SPM:
        // Auth.auth().signIn(withEmail: email, ...)
        isSignedIn = true
        userEmail = email
        syncStatusMessage = "Connected as \(email)"
        completion(.success(()))
    }
    
    public func signOut() {
        isSignedIn = false
        userEmail = nil
        syncStatusMessage = "Signed out"
    }
    
    public func triggerSync() async {
        guard isConfigured else { return }
        
        isSyncing = true
        syncStatusMessage = "Syncing garage, rides & expenses..."
        
        // Simulating or driving Firestore collection synchronization:
        // Users/{uid}/expenses, Users/{uid}/garage, Users/{uid}/rides
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        
        isSyncing = false
        lastSyncTime = Date()
        syncStatusMessage = "Synced just now"
    }
}
