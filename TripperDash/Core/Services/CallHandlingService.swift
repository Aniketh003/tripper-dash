import Foundation
import SwiftUI
import Darwin
#if os(iOS)
import CallKit
import AVFoundation
import UIKit
#endif

@Observable
public final class CallHandlingService: NSObject, @unchecked Sendable {
    public static let shared = CallHandlingService()
    
    public var isRinging: Bool = false
    public var isOngoing: Bool = false
    public var isSimulatedCall: Bool = false
    public var callerName: String = "Incoming Call"
    public var callDurationSeconds: UInt32 = 0
    public var activeAudioDeviceName: String = "iPhone"
    public var statusNote: String? = nil
    
    #if os(iOS)
    private let callObserver = CXCallObserver()
    private let callController = CXCallController()
    private var activeCallUUID: UUID?
    private var callMonitorTimer: DispatchSourceTimer?
    
    // Dynamic MediaRemote & TelephonyUtilities bridges
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private var mrSendCommand: MRMediaRemoteSendCommandFn?
    #endif
    private var callDurationTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.tripperdash.calltimer", qos: .userInteractive)
    
    private override init() {
        super.init()
        #if os(iOS)
        setupDynamicTelephonyBridges()
        callObserver.setDelegate(self, queue: .main)
        detectConnectedAudioDevice()
        startBackgroundCallMonitor()
        #endif
    }
    
    public var formattedDuration: String {
        let mins = callDurationSeconds / 60
        let secs = callDurationSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    #if os(iOS)
    private func setupDynamicTelephonyBridges() {
        _ = dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_NOW)
        if let mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
           let sym = dlsym(mrHandle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFn.self)
        }
    }
    
    /// Queries `TUCallCenter.sharedInstance()` dynamically if accessible to read caller ID or active `TUCall` objects.
    private func activeTUCalls() -> (center: NSObject, calls: [NSObject])? {
        guard let cls = NSClassFromString("TUCallCenter") as? NSObject.Type else { return nil }
        let sharedSel = NSSelectorFromString("sharedInstance")
        guard cls.responds(to: sharedSel),
              let center = cls.perform(sharedSel)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        for prop in ["currentCalls", "currentAudioAndVideoCalls"] {
            let sel = NSSelectorFromString(prop)
            if center.responds(to: sel),
               let arr = center.perform(sel)?.takeUnretainedValue() as? [NSObject],
               !arr.isEmpty {
                return (center, arr)
            }
        }
        for singleProp in ["incomingCall", "frontmostCall", "frontmostAudioOrVideoCall"] {
            let sel = NSSelectorFromString(singleProp)
            if center.responds(to: sel),
               let callObj = center.perform(sel)?.takeUnretainedValue() as? NSObject {
                return (center, [callObj])
            }
        }
        return (center, [])
    }
    
    private func resolveCallerNameFromTUCalls(defaultName: String) -> String {
        guard let (_, calls) = activeTUCalls(), let first = calls.first else {
            return defaultName
        }
        for key in ["displayName", "callerNameFromNetwork", "suggestedDisplayName", "contactIdentifier"] {
            let sel = NSSelectorFromString(key)
            if first.responds(to: sel),
               let str = first.perform(sel)?.takeUnretainedValue() as? String,
               !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return str
            }
        }
        let handleSel = NSSelectorFromString("handle")
        if first.responds(to: handleSel),
           let handleObj = first.perform(handleSel)?.takeUnretainedValue() as? NSObject {
            let valSel = NSSelectorFromString("value")
            if handleObj.responds(to: valSel),
               let val = handleObj.perform(valSel)?.takeUnretainedValue() as? String,
               !val.isEmpty {
                return val
            }
        }
        return defaultName
    }
    
    /// Attempt to answer via `TUCallCenter` (`answerCall:`) if available on device.
    @discardableResult
    private func answerViaTelephonyUtilities() -> Bool {
        guard let (center, calls) = activeTUCalls(), let callObj = calls.first else { return false }
        let answerSel = NSSelectorFromString("answerCall:")
        if center.responds(to: answerSel) {
            _ = center.perform(answerSel, with: callObj)
            return true
        }
        let answerWithReqSel = NSSelectorFromString("answerWithRequest:")
        if center.responds(to: answerWithReqSel),
           let reqCls = NSClassFromString("TUAnswerRequest") as? NSObject.Type {
            let initSel = NSSelectorFromString("initWithCall:")
            let allocObj = reqCls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
            if let req = allocObj?.perform(initSel, with: callObj)?.takeUnretainedValue() {
                _ = center.perform(answerWithReqSel, with: req)
                return true
            }
        }
        return false
    }
    
    /// Attempt to disconnect/reject via `TUCallCenter` (`disconnectCall:` / `disconnectAllCalls`) if available.
    @discardableResult
    private func disconnectViaTelephonyUtilities() -> Bool {
        guard let (center, calls) = activeTUCalls() else { return false }
        let discSel = NSSelectorFromString("disconnectCall:")
        if let callObj = calls.first, center.responds(to: discSel) {
            _ = center.perform(discSel, with: callObj)
            return true
        }
        let discAllSel = NSSelectorFromString("disconnectAllCalls")
        if center.responds(to: discAllSel) {
            _ = center.perform(discAllSel)
            return true
        }
        return false
    }
    
    /// Polls `CXCallObserver.calls` on a background-safe GCD timer every 0.3s so incoming/ongoing
    /// carrier & VoIP calls are detected immediately even when iOS puts the app in background during ringtone!
    private func startBackgroundCallMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 0.3, repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.isSimulatedCall else { return }
            let calls = self.callObserver.calls
            if let activeCall = calls.first(where: { !$0.hasEnded }) {
                self.syncSystemCallState(activeCall)
            } else if self.isRinging || self.isOngoing {
                DispatchQueue.main.async {
                    guard !self.isSimulatedCall else { return }
                    self.isRinging = false
                    self.isOngoing = false
                    self.statusNote = nil
                    self.stopCallTimer()
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.callerName,
                        isRinging: false,
                        isOngoing: false,
                        durationSeconds: 0
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            }
        }
        timer.resume()
        self.callMonitorTimer = timer
    }
    
    private func syncSystemCallState(_ call: CXCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeCallUUID = call.uuid
            self.isSimulatedCall = false
            
            if call.hasEnded {
                if self.isRinging || self.isOngoing {
                    self.isRinging = false
                    self.isOngoing = false
                    self.statusNote = nil
                    self.stopCallTimer()
                    TripperDashClient.shared.log("📞 Phone Call Ended")
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.callerName,
                        isRinging: false,
                        isOngoing: false,
                        durationSeconds: 0
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            } else if call.hasConnected {
                if !self.isOngoing || self.isRinging {
                    self.isRinging = false
                    self.isOngoing = true
                    let defaultLabel = (self.callerName.isEmpty || self.callerName == "Incoming Call" || self.callerName == "Dialing...") ? "Active Call" : self.callerName
                    self.callerName = self.resolveCallerNameFromTUCalls(defaultName: defaultLabel)
                    self.startCallTimer()
                    self.detectConnectedAudioDevice()
                    TripperDashClient.shared.log("📞 Phone Call Connected (\(self.callerName))")
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.callerName,
                        isRinging: false,
                        isOngoing: true,
                        durationSeconds: self.callDurationSeconds
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            } else {
                // Ringing (Incoming or Outgoing Dialing)
                let fallbackLabel = call.isOutgoing ? "Outgoing Call" : "Incoming Call"
                let resolvedName = self.resolveCallerNameFromTUCalls(defaultName: fallbackLabel)
                if !self.isRinging || self.callerName != resolvedName {
                    let wasAlreadyRinging = self.isRinging
                    self.isRinging = true
                    self.isOngoing = false
                    self.callerName = resolvedName
                    self.detectConnectedAudioDevice()
                    if !wasAlreadyRinging {
                        self.startCallTimer()
                        TripperDashClient.shared.log("📞 \(self.callerName) ringing — projecting Call Popup to TFT Dash!")
                    }
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.callerName,
                        isRinging: true,
                        isOngoing: false,
                        durationSeconds: 0
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            }
        }
    }
    #endif
    
    /// Runs a 1Hz timer while EITHER `isRinging` OR `isOngoing` is true so the TFT Dash
    /// continuously receives call alert cards (`05 21`, `05 4D`, `05 22`) and updates call duration.
    private func startCallTimer() {
        stopCallTimer(resetDuration: false)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, (self.isRinging || self.isOngoing) else { return }
            DispatchQueue.main.async {
                if self.isOngoing {
                    self.callDurationSeconds += 1
                }
                TripperDashClient.shared.sendCallAlert(
                    callerName: self.callerName,
                    isRinging: self.isRinging,
                    isOngoing: self.isOngoing,
                    durationSeconds: self.callDurationSeconds
                )
                TFTProjectionService.shared.triggerImmediateFrame()
            }
        }
        timer.resume()
        self.callDurationTimer = timer
    }
    
    private func stopCallTimer(resetDuration: Bool = true) {
        callDurationTimer?.cancel()
        callDurationTimer = nil
        if resetDuration {
            callDurationSeconds = 0
        }
    }
    
    // MARK: - Handlebar & In-App Call Actions
    
    public func answerCall() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isRinging else { return }
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if !self.isSimulatedCall {
                let answeredViaTU = self.answerViaTelephonyUtilities()
                if let uuid = self.activeCallUUID {
                    let answerAction = CXAnswerCallAction(call: uuid)
                    let transaction = CXTransaction(action: answerAction)
                    self.callController.request(transaction) { [weak self] error in
                        if let error = error, !answeredViaTU {
                            // Fallback: send headset hook / toggle command via MediaRemote
                            _ = self?.mrSendCommand?(2, nil)
                            DispatchQueue.main.async {
                                self?.statusNote = "Call answered via headset bridge"
                                TripperDashClient.shared.log("ℹ️ CallKit answer fallback (\(error.localizedDescription)) — triggered headset hook")
                            }
                        }
                    }
                } else if !answeredViaTU {
                    _ = self.mrSendCommand?(2, nil)
                }
            }
            #endif
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = false
                self.isOngoing = true
            }
            self.callDurationSeconds = 0
            self.detectConnectedAudioDevice()
            self.startCallTimer()
            
            TripperDashClient.shared.log("📞 Answered call: \(self.callerName)")
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: 0
            )
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    
    public func endOrRejectCall() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isRinging || self.isOngoing else { return }
            
            let wasRinging = self.isRinging
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if !self.isSimulatedCall {
                let endedViaTU = self.disconnectViaTelephonyUtilities()
                if let uuid = self.activeCallUUID {
                    let endAction = CXEndCallAction(call: uuid)
                    let transaction = CXTransaction(action: endAction)
                    self.callController.request(transaction) { [weak self] error in
                        if let error = error, !endedViaTU {
                            // Fallback: send stop/headset hangup command via MediaRemote
                            _ = self?.mrSendCommand?(1, nil)
                            DispatchQueue.main.async {
                                self?.statusNote = "Call ended via headset bridge"
                                TripperDashClient.shared.log("ℹ️ CallKit end fallback (\(error.localizedDescription)) — triggered headset hangup")
                            }
                        }
                    }
                } else if !endedViaTU {
                    _ = self.mrSendCommand?(1, nil)
                }
            }
            #endif
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = false
                self.isOngoing = false
                self.isSimulatedCall = false
                self.statusNote = nil
            }
            self.stopCallTimer()
            
            TripperDashClient.shared.log(wasRinging ? "📞 Declined call: \(self.callerName)" : "📞 Ended call: \(self.callerName)")
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: false,
                durationSeconds: 0
            )
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    
    // MARK: - Simulated Call Trigger for Desk Testing
    
    public func simulateIncomingCall(caller: String = "Royal Enfield Rider") {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            self.stopCallTimer()
            self.isSimulatedCall = true
            self.callerName = caller
            self.statusNote = nil
            self.detectConnectedAudioDevice()
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = true
                self.isOngoing = false
            }
            self.startCallTimer()
            
            TripperDashClient.shared.sendCallAlert(
                callerName: caller,
                isRinging: true,
                isOngoing: false,
                durationSeconds: 0
            )
            TFTProjectionService.shared.triggerImmediateFrame()
            TripperDashClient.shared.log("📞 Incoming call: '\(caller)' — Press Left/Up/Center to Answer, Right/Down to Decline")
        }
    }
    
    // MARK: - Bluetooth Headset / Earphones Audio Route Detection
    
    public func detectConnectedAudioDevice() {
        #if os(iOS)
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                activeAudioDeviceName = output.portName
                return
            }
        }
        activeAudioDeviceName = "iPhone Speaker"
        #else
        activeAudioDeviceName = "Mac Audio"
        #endif
    }
}

#if os(iOS)
extension CallHandlingService: CXCallObserverDelegate {
    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        syncSystemCallState(call)
    }
}
#endif
