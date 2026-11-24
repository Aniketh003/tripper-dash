import Foundation
import SwiftUI
import Darwin
#if os(iOS)
import CallKit
import CoreTelephony
import AVFoundation
import UIKit
#endif

@Observable
public final class CallHandlingService: NSObject, @unchecked Sendable {
    public static let shared = CallHandlingService()
    
    public var isRinging: Bool = false
    public var isOngoing: Bool = false
    public var isSimulatedCall: Bool = false
    public var callerName: String = ""
    public var callDurationSeconds: UInt32 = 0
    public var activeAudioDeviceName: String = "iPhone"
    public var statusNote: String? = nil
    
    #if os(iOS)
    private let callObserver = CXCallObserver()
    private let backgroundCallObserver = CXCallObserver()
    private let callController = CXCallController()
    private var activeCallUUID: UUID?
    private var answeredCallUUIDs: Set<UUID> = []
    private var dismissedCallUUIDs: Set<UUID> = []
    private var callMonitorTimer: DispatchSourceTimer?
    
    // Dynamic CoreTelephony, TelephonyUtilities & MediaRemote bridges
    private typealias CTCopyCurrentCallsFn = @convention(c) (CFAllocator?) -> CFArray?
    private typealias CTCallAnswerFn = @convention(c) (AnyObject) -> Void
    private typealias CTCallDisconnectFn = @convention(c) (AnyObject) -> Void
    private typealias CTCallListDisconnectFn = @convention(c) () -> Void
    private typealias CTCallCopyAddressFn = @convention(c) (CFAllocator?, AnyObject) -> CFString?
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    
    private var ctCopyCurrentCalls: CTCopyCurrentCallsFn?
    private var ctCallAnswer: CTCallAnswerFn?
    private var ctCallDisconnect: CTCallDisconnectFn?
    private var ctCallListDisconnect: CTCallListDisconnectFn?
    private var ctCallCopyAddress: CTCallCopyAddressFn?
    private var mrSendCommand: MRMediaRemoteSendCommandFn?
    #endif
    private var callDurationTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.tripperdash.calltimer", qos: .userInteractive)
    
    private static let genericPlaceholders: Set<String> = [
        "", "Incoming Call", "Outgoing Call", "Ongoing Call", "Active Call", "Dialing...", "Dialing…"
    ]
    
    private override init() {
        super.init()
        #if os(iOS)
        setupDynamicTelephonyBridges()
        callObserver.setDelegate(self, queue: .main)
        backgroundCallObserver.setDelegate(self, queue: timerQueue)
        detectConnectedAudioDevice()
        startBackgroundCallMonitor()
        #endif
    }
    
    public var formattedDuration: String {
        let mins = callDurationSeconds / 60
        let secs = callDurationSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    /// Ensures the displayed caller title never says "Incoming Call" while a call is ongoing.
    public var displayTitle: String {
        let trimmed = callerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isOngoing {
            if Self.genericPlaceholders.contains(trimmed) {
                return "Ongoing Call"
            }
            return trimmed
        } else if isRinging {
            if Self.genericPlaceholders.contains(trimmed) {
                return "Incoming Call"
            }
            return trimmed
        }
        return trimmed.isEmpty ? "Phone Call" : trimmed
    }
    
    #if os(iOS)
    private func setupDynamicTelephonyBridges() {
        _ = dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_NOW)
        
        if let ctHandle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW) {
            if let sym = dlsym(ctHandle, "CTCopyCurrentCalls") {
                ctCopyCurrentCalls = unsafeBitCast(sym, to: CTCopyCurrentCallsFn.self)
            }
            if let sym = dlsym(ctHandle, "CTCallAnswer") {
                ctCallAnswer = unsafeBitCast(sym, to: CTCallAnswerFn.self)
            }
            if let sym = dlsym(ctHandle, "CTCallDisconnect") {
                ctCallDisconnect = unsafeBitCast(sym, to: CTCallDisconnectFn.self)
            }
            if let sym = dlsym(ctHandle, "CTCallListDisconnect") {
                ctCallListDisconnect = unsafeBitCast(sym, to: CTCallListDisconnectFn.self)
            }
            if let sym = dlsym(ctHandle, "CTCallCopyAddress") {
                ctCallCopyAddress = unsafeBitCast(sym, to: CTCallCopyAddressFn.self)
            }
        }
        
        if let mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
           let sym = dlsym(mrHandle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(sym, to: MRMediaRemoteSendCommandFn.self)
        }
    }
    
    private func activeCTCalls() -> [AnyObject] {
        guard let copyFn = ctCopyCurrentCalls else { return [] }
        if let arr = copyFn(kCFAllocatorDefault) as? [AnyObject], !arr.isEmpty {
            return arr
        }
        if let arr = copyFn(nil) as? [AnyObject], !arr.isEmpty {
            return arr
        }
        return []
    }
    
    @discardableResult
    private func answerViaCoreTelephony() -> Bool {
        let ctCalls = activeCTCalls()
        guard !ctCalls.isEmpty, let answerFn = ctCallAnswer else { return false }
        for callObj in ctCalls {
            answerFn(callObj)
        }
        return true
    }
    
    @discardableResult
    private func disconnectViaCoreTelephony() -> Bool {
        var didDisconnect = false
        let ctCalls = activeCTCalls()
        if !ctCalls.isEmpty, let discFn = ctCallDisconnect {
            for callObj in ctCalls {
                discFn(callObj)
            }
            didDisconnect = true
        }
        if let listDiscFn = ctCallListDisconnect {
            listDiscFn()
            didDisconnect = true
        }
        return didDisconnect
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
        for singleProp in ["incomingCall", "frontmostCall", "frontmostAudioOrVideoCall", "displayedCall"] {
            let sel = NSSelectorFromString(singleProp)
            if center.responds(to: sel),
               let callObj = center.perform(sel)?.takeUnretainedValue() as? NSObject {
                return (center, [callObj])
            }
        }
        return (center, [])
    }
    
    private func resolveCallerNameFromSystem(defaultName: String) -> String {
        if let (_, calls) = activeTUCalls(), let first = calls.first {
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
        }
        if let addrFn = ctCallCopyAddress {
            for ctCall in activeCTCalls() {
                if let cfStr = addrFn(kCFAllocatorDefault, ctCall) {
                    let str = (cfStr as String).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty {
                        return str
                    }
                }
            }
        }
        return defaultName
    }
    
    /// Attempt to answer via `TUCallCenter` (`answerCall:` / `answerWithRequest:`) if available on device.
    @discardableResult
    private func answerViaTelephonyUtilities() -> Bool {
        guard let (center, calls) = activeTUCalls(), let callObj = calls.first else { return false }
        var handled = false
        let answerSel = NSSelectorFromString("answerCall:")
        if center.responds(to: answerSel) {
            _ = center.perform(answerSel, with: callObj)
            handled = true
        }
        let answerWithReqSel = NSSelectorFromString("answerWithRequest:")
        if center.responds(to: answerWithReqSel),
           let reqCls = NSClassFromString("TUAnswerRequest") as? NSObject.Type {
            let initSel = NSSelectorFromString("initWithCall:")
            let allocObj = reqCls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
            if let req = allocObj?.perform(initSel, with: callObj)?.takeUnretainedValue() {
                _ = center.perform(answerWithReqSel, with: req)
                handled = true
            }
        }
        return handled
    }
    
    /// Attempt to disconnect/reject via `TUCallCenter` (`disconnectCall:` / `disconnectAllCalls`) if available.
    @discardableResult
    private func disconnectViaTelephonyUtilities() -> Bool {
        guard let (center, calls) = activeTUCalls() else { return false }
        var handled = false
        let discSel = NSSelectorFromString("disconnectCall:")
        if let callObj = calls.first, center.responds(to: discSel) {
            _ = center.perform(discSel, with: callObj)
            handled = true
        }
        let discCurrentSel = NSSelectorFromString("disconnectCurrentCallAndActivateHeld")
        if center.responds(to: discCurrentSel) {
            _ = center.perform(discCurrentSel)
            handled = true
        }
        let discAllSel = NSSelectorFromString("disconnectAllCalls")
        if center.responds(to: discAllSel) {
            _ = center.perform(discAllSel)
            handled = true
        }
        return handled
    }
    
    /// Polls both main and background `CXCallObserver.calls` every 0.3s so incoming/ongoing
    /// calls are tracked immediately even when iOS puts the app in background during ringtone.
    private func startBackgroundCallMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 0.3, repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.isSimulatedCall else { return }
            let bgCalls = self.backgroundCallObserver.calls
            let mainCalls = self.callObserver.calls
            let allCalls = bgCalls.isEmpty ? mainCalls : bgCalls
            let nonEnded = allCalls.filter { !$0.hasEnded }
            
            if nonEnded.isEmpty {
                DispatchQueue.main.async {
                    guard !self.isSimulatedCall else { return }
                    self.answeredCallUUIDs.removeAll()
                    self.dismissedCallUUIDs.removeAll()
                    if self.isRinging || self.isOngoing {
                        self.isRinging = false
                        self.isOngoing = false
                        self.callerName = ""
                        self.statusNote = nil
                        self.stopCallTimer()
                        TripperDashClient.shared.sendCallAlert(
                            callerName: "",
                            isRinging: false,
                            isOngoing: false,
                            durationSeconds: 0
                        )
                        TFTProjectionService.shared.triggerImmediateFrame()
                    }
                }
                return
            }
            
            // Prioritize connected calls first so an ongoing call never shows as ringing
            let activeCall = nonEnded.first(where: { $0.hasConnected })
                ?? nonEnded.first(where: { $0.isOutgoing })
                ?? nonEnded.first
            if let call = activeCall {
                self.syncSystemCallState(call)
            }
        }
        timer.resume()
        self.callMonitorTimer = timer
    }
    
    private func syncSystemCallState(_ call: CXCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isSimulatedCall else { return }
            
            if call.hasEnded {
                self.answeredCallUUIDs.remove(call.uuid)
                self.dismissedCallUUIDs.remove(call.uuid)
                let remaining = self.backgroundCallObserver.calls.filter { !$0.hasEnded && $0.uuid != call.uuid }
                if let nextCall = remaining.first {
                    self.syncSystemCallState(nextCall)
                    return
                }
                if self.isRinging || self.isOngoing {
                    self.isRinging = false
                    self.isOngoing = false
                    self.callerName = ""
                    self.statusNote = nil
                    self.stopCallTimer()
                    TripperDashClient.shared.log("📞 Phone Call Ended")
                    TripperDashClient.shared.sendCallAlert(
                        callerName: "",
                        isRinging: false,
                        isOngoing: false,
                        durationSeconds: 0
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
                return
            }
            
            // If rider already dismissed/dropped this call UUID, do not re-show it while iOS finishes teardown
            if self.dismissedCallUUIDs.contains(call.uuid) {
                return
            }
            
            self.activeCallUUID = call.uuid
            
            // Treat as ONGOING if call has connected, is on hold, is outgoing, or rider already pressed Answer
            let isCallActiveOrAnswered = call.hasConnected || call.isOnHold || call.isOutgoing || self.answeredCallUUIDs.contains(call.uuid)
            
            if isCallActiveOrAnswered {
                let wasOngoing = self.isOngoing && !self.isRinging
                self.isRinging = false
                self.isOngoing = true
                
                // Always ensure callerName is NEVER left as "Incoming Call" during an ongoing call
                let currentTrimmed = self.callerName.trimmingCharacters(in: .whitespacesAndNewlines)
                let existingContact = Self.genericPlaceholders.contains(currentTrimmed) ? "Ongoing Call" : currentTrimmed
                let resolved = self.resolveCallerNameFromSystem(defaultName: existingContact)
                self.callerName = Self.genericPlaceholders.contains(resolved) ? "Ongoing Call" : resolved
                
                if !wasOngoing {
                    self.callDurationSeconds = 0
                    self.startCallTimer()
                    self.detectConnectedAudioDevice()
                    TripperDashClient.shared.log("📞 Ongoing Call Active (\(self.displayTitle))")
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.displayTitle,
                        isRinging: false,
                        isOngoing: true,
                        durationSeconds: self.callDurationSeconds
                    )
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            } else {
                // Incoming Ringing Call
                let currentTrimmed = self.callerName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackLabel = (!Self.genericPlaceholders.contains(currentTrimmed)) ? currentTrimmed : "Incoming Call"
                let resolvedName = self.resolveCallerNameFromSystem(defaultName: fallbackLabel)
                
                if !self.isRinging || self.isOngoing || self.callerName != resolvedName {
                    let wasAlreadyRinging = self.isRinging
                    self.isRinging = true
                    self.isOngoing = false
                    self.callerName = resolvedName
                    self.detectConnectedAudioDevice()
                    if !wasAlreadyRinging {
                        self.callDurationSeconds = 0
                        self.startCallTimer()
                        TripperDashClient.shared.log("📞 \(self.displayTitle) ringing — showing on TFT Dash")
                    }
                    TripperDashClient.shared.sendCallAlert(
                        callerName: self.displayTitle,
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
    
    /// Runs a 1Hz timer while EITHER `isRinging` OR `isOngoing` is true to update call duration and refresh TFT frames.
    private func startCallTimer() {
        stopCallTimer(resetDuration: false)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, (self.isRinging || self.isOngoing) else { return }
            DispatchQueue.main.async {
                if self.isOngoing {
                    self.callDurationSeconds += 1
                    if Self.genericPlaceholders.contains(self.callerName.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        self.callerName = "Ongoing Call"
                    }
                }
                TripperDashClient.shared.sendCallAlert(
                    callerName: self.displayTitle,
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
            if let uuid = self.activeCallUUID {
                self.answeredCallUUIDs.insert(uuid)
            }
            for c in self.callObserver.calls where !c.hasEnded {
                self.answeredCallUUIDs.insert(c.uuid)
            }
            for c in self.backgroundCallObserver.calls where !c.hasEnded {
                self.answeredCallUUIDs.insert(c.uuid)
            }
            
            if !self.isSimulatedCall {
                let answeredCT = self.answerViaCoreTelephony()
                let answeredTU = self.answerViaTelephonyUtilities()
                
                var targetUUIDs: Set<UUID> = []
                if let uuid = self.activeCallUUID { targetUUIDs.insert(uuid) }
                for c in self.callObserver.calls where !c.hasEnded { targetUUIDs.insert(c.uuid) }
                for c in self.backgroundCallObserver.calls where !c.hasEnded { targetUUIDs.insert(c.uuid) }
                
                if !targetUUIDs.isEmpty {
                    for uuid in targetUUIDs {
                        let answerAction = CXAnswerCallAction(call: uuid)
                        let transaction = CXTransaction(action: answerAction)
                        self.callController.request(transaction) { [weak self] error in
                            if error != nil && !answeredCT && !answeredTU {
                                _ = self?.mrSendCommand?(2, nil)
                            }
                        }
                    }
                } else if !answeredCT && !answeredTU {
                    _ = self.mrSendCommand?(2, nil)
                }
            }
            #endif
            
            // Update callerName immediately so it never displays "Incoming Call" while ongoing
            let trimmed = self.callerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.genericPlaceholders.contains(trimmed) {
                self.callerName = "Ongoing Call"
            }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = false
                self.isOngoing = true
            }
            self.callDurationSeconds = 0
            self.detectConnectedAudioDevice()
            self.startCallTimer()
            
            TripperDashClient.shared.log("📞 Answered call: \(self.displayTitle)")
            TripperDashClient.shared.sendCallAlert(
                callerName: self.displayTitle,
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
            let endedLabel = self.displayTitle
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if let uuid = self.activeCallUUID {
                self.dismissedCallUUIDs.insert(uuid)
                self.answeredCallUUIDs.remove(uuid)
            }
            for c in self.callObserver.calls where !c.hasEnded {
                self.dismissedCallUUIDs.insert(c.uuid)
                self.answeredCallUUIDs.remove(c.uuid)
            }
            for c in self.backgroundCallObserver.calls where !c.hasEnded {
                self.dismissedCallUUIDs.insert(c.uuid)
                self.answeredCallUUIDs.remove(c.uuid)
            }
            
            if !self.isSimulatedCall {
                let endedCT = self.disconnectViaCoreTelephony()
                let endedTU = self.disconnectViaTelephonyUtilities()
                
                var targetUUIDs: Set<UUID> = []
                if let uuid = self.activeCallUUID { targetUUIDs.insert(uuid) }
                for c in self.callObserver.calls where !c.hasEnded { targetUUIDs.insert(c.uuid) }
                for c in self.backgroundCallObserver.calls where !c.hasEnded { targetUUIDs.insert(c.uuid) }
                
                if !targetUUIDs.isEmpty {
                    for uuid in targetUUIDs {
                        let endAction = CXEndCallAction(call: uuid)
                        let transaction = CXTransaction(action: endAction)
                        self.callController.request(transaction) { [weak self] error in
                            if error != nil && !endedCT && !endedTU {
                                _ = self?.mrSendCommand?(3, nil)
                            }
                        }
                    }
                } else if !endedCT && !endedTU {
                    _ = self.mrSendCommand?(3, nil)
                }
            }
            #endif
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = false
                self.isOngoing = false
                self.isSimulatedCall = false
                self.callerName = ""
                self.statusNote = nil
            }
            self.stopCallTimer()
            
            TripperDashClient.shared.log(wasRinging ? "📞 Declined call: \(endedLabel)" : "📞 Ended call: \(endedLabel)")
            TripperDashClient.shared.sendCallAlert(
                callerName: "",
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
            self.answeredCallUUIDs.removeAll()
            self.dismissedCallUUIDs.removeAll()
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
