import Foundation
import CryptoKit
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

/// Native Spotify OAuth 2.0 PKCE + Web API Player Controller.
/// Allows TripperDash to read live Spotify Now Playing metadata (Song, Artist, Album, Play state)
/// and control Spotify playback (Play/Pause, Next, Previous) from the Royal Enfield handlebar joystick
/// even when TripperDash is in the background or the iPhone screen is locked.
@Observable
public final class SpotifyService: NSObject, @unchecked Sendable {
    public static let shared = SpotifyService()
    
    public static let redirectURI = "tripperdash://spotify-callback"
    
    public var clientId: String = "" {
        didSet {
            let trimmed = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: "pref_spotify_client_id")
        }
    }
    public var isConnected: Bool = false
    public var isAuthenticating: Bool = false
    public var authStatusMessage: String = ""
    
    public var trackTitle: String = ""
    public var trackArtist: String = ""
    public var trackAlbum: String = ""
    public var isPlaying: Bool = false
    
    private var accessToken: String? {
        didSet { UserDefaults.standard.set(accessToken, forKey: "pref_spotify_access_token") }
    }
    private var refreshToken: String? {
        didSet { UserDefaults.standard.set(refreshToken, forKey: "pref_spotify_refresh_token") }
    }
    private var tokenExpiryDate: Date? {
        didSet { UserDefaults.standard.set(tokenExpiryDate, forKey: "pref_spotify_token_expiry") }
    }
    
    private var codeVerifier: String = ""
    #if os(iOS)
    private var authSession: ASWebAuthenticationSession?
    #endif
    
    private override init() {
        super.init()
        self.clientId = UserDefaults.standard.string(forKey: "pref_spotify_client_id") ?? ""
        self.accessToken = UserDefaults.standard.string(forKey: "pref_spotify_access_token")
        self.refreshToken = UserDefaults.standard.string(forKey: "pref_spotify_refresh_token")
        self.tokenExpiryDate = UserDefaults.standard.object(forKey: "pref_spotify_token_expiry") as? Date
        self.isConnected = (self.accessToken != nil && !(self.accessToken?.isEmpty ?? true))
    }
    
    // MARK: - OAuth 2.0 PKCE Login Flow
    
    public func startAuthorization() {
        let cleanClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanClientId.isEmpty else {
            authStatusMessage = "Enter your Spotify Client ID first."
            return
        }
        
        let verifier = Self.generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = Self.generateCodeChallenge(from: verifier)
        
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: cleanClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-read-currently-playing user-modify-playback-state")
        ]
        
        guard let authURL = comps.url else { return }
        
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isAuthenticating = true
            self.authStatusMessage = "Opening Spotify authorization…"
            
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "tripperdash"
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }
                DispatchQueue.main.async { self.isAuthenticating = false }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.authStatusMessage = "Auth cancelled: \(error.localizedDescription)"
                    }
                    return
                }
                guard let callbackURL = callbackURL else { return }
                self.handleCallbackURL(callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
        #endif
    }
    
    public func handleCallbackURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            DispatchQueue.main.async {
                self.authStatusMessage = "No authorization code returned from Spotify."
            }
            return
        }
        exchangeCodeForTokens(code: code)
    }
    
    private func exchangeCodeForTokens(code: String) {
        let cleanClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComps = URLComponents()
        bodyComps.queryItems = [
            URLQueryItem(name: "client_id", value: cleanClientId),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.authStatusMessage = "Token exchange failed."
                }
                return
            }
            self.parseTokenResponse(data: data)
        }.resume()
    }
    
    public func refreshAccessTokenIfNeeded(completion: @escaping (String?) -> Void) {
        if let token = accessToken,
           let expiry = tokenExpiryDate,
           Date().addingTimeInterval(60) < expiry {
            completion(token)
            return
        }
        
        guard let refresh = refreshToken, !refresh.isEmpty,
              let url = URL(string: "https://accounts.spotify.com/api/token") else {
            completion(accessToken)
            return
        }
        
        let cleanClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComps = URLComponents()
        bodyComps.queryItems = [
            URLQueryItem(name: "client_id", value: cleanClientId),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh)
        ]
        req.httpBody = bodyComps.percentEncodedQuery?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data else {
                completion(self?.accessToken)
                return
            }
            self.parseTokenResponse(data: data)
            completion(self.accessToken)
        }.resume()
    }
    
    private func parseTokenResponse(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let desc = errJson["error_description"] as? String {
                DispatchQueue.main.async {
                    self.authStatusMessage = "Spotify error: \(desc)"
                }
            }
            return
        }
        
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let newRefresh = json["refresh_token"] as? String
        
        DispatchQueue.main.async {
            self.accessToken = token
            if let r = newRefresh, !r.isEmpty {
                self.refreshToken = r
            }
            self.tokenExpiryDate = Date().addingTimeInterval(expiresIn)
            self.isConnected = true
            self.authStatusMessage = "Connected to Spotify"
            TripperDashClient.shared.log("🟢 Spotify linked! Live track metadata & handlebar controls active.")
            self.fetchCurrentlyPlaying { _ in }
        }
    }
    
    public func disconnect() {
        DispatchQueue.main.async {
            self.accessToken = nil
            self.refreshToken = nil
            self.tokenExpiryDate = nil
            self.isConnected = false
            self.trackTitle = ""
            self.trackArtist = ""
            self.trackAlbum = ""
            self.authStatusMessage = "Disconnected"
        }
    }
    
    // MARK: - Live Spotify Now Playing Poll & Playback Commands
    
    public func fetchCurrentlyPlaying(completion: @escaping (Bool) -> Void) {
        guard isConnected else {
            completion(false)
            return
        }
        
        refreshAccessTokenIfNeeded { [weak self] token in
            guard let self = self, let token = token, !token.isEmpty,
                  let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
                completion(false)
                return
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 4.0
            
            URLSession.shared.dataTask(with: req) { data, response, error in
                guard error == nil, let http = response as? HTTPURLResponse else {
                    completion(false)
                    return
                }
                if http.statusCode == 204 {
                    // Nothing currently active in Spotify
                    DispatchQueue.main.async {
                        self.isPlaying = false
                        completion(true)
                    }
                    return
                }
                guard http.statusCode == 200, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(false)
                    return
                }
                
                let playing = (json["is_playing"] as? Bool) ?? false
                var title = ""
                var artist = ""
                var album = ""
                
                if let item = json["item"] as? [String: Any] {
                    title = (item["name"] as? String) ?? ""
                    if let artists = item["artists"] as? [[String: Any]] {
                        artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    }
                    if let alb = item["album"] as? [String: Any] {
                        album = (alb["name"] as? String) ?? ""
                    }
                }
                
                DispatchQueue.main.async {
                    if !title.isEmpty {
                        self.trackTitle = title
                        self.trackArtist = artist
                        self.trackAlbum = album
                    }
                    self.isPlaying = playing
                    completion(true)
                }
            }.resume()
        }
    }
    
    public func sendPlayerCommand(endpoint: String, method: String, completion: @escaping (Bool) -> Void) {
        guard isConnected else {
            completion(false)
            return
        }
        
        refreshAccessTokenIfNeeded { token in
            guard let token = token, !token.isEmpty,
                  let url = URL(string: "https://api.spotify.com/v1/me/player/\(endpoint)") else {
                completion(false)
                return
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("0", forHTTPHeaderField: "Content-Length")
            req.timeoutInterval = 4.0
            
            URLSession.shared.dataTask(with: req) { _, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let ok = (error == nil) && (200...299).contains(code)
                completion(ok)
            }.resume()
        }
    }
    
    // MARK: - PKCE Crypto Helpers
    
    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private static func generateCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if os(iOS)
extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
#endif
