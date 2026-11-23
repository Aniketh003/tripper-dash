import Foundation
import SwiftUI
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
    #endif
    private var callTimer: Timer?
    
    private override init() {
        super.init()
        #if os(iOS)
        callObserver.setDelegate(self, queue: .main)
        detectConnectedAudioDevice()
        #endif
    }
    
    public var formattedDuration: String {
        let mins = callDurationSeconds / 60
        let secs = callDurationSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func startCallTimer() {
        callTimer?.invalidate()
        callDurationSeconds = 0
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isOngoing else { return }
            self.callDurationSeconds += 1
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: self.callDurationSeconds
            )
        }
    }
    
    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callDurationSeconds = 0
    }
    
    // MARK: - Handlebar & In-App Call Actions
    
    public func answerCall() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isRinging else { return }
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let uuid = self.activeCallUUID, !self.isSimulatedCall {
                let answerAction = CXAnswerCallAction(call: uuid)
                let transaction = CXTransaction(action: answerAction)
                self.callController.request(transaction) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            // iOS restricts third-party apps from answering carrier cellular calls via CallKit
                            self.statusNote = "Carrier calls answer via Bluetooth headset/intercom"
                            TripperDashClient.shared.log("ℹ️ iOS CallKit note: \(error.localizedDescription)")
                        }
                    }
                }
            }
            #endif
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isRinging = false
                self.isOngoing = true
            }
            self.detectConnectedAudioDevice()
            self.startCallTimer()
            
            TripperDashClient.shared.log("📞 Answered call: \(self.callerName)")
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: 0
            )
        }
    }
    
    public func endOrRejectCall() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isRinging || self.isOngoing else { return }
            
            let wasRinging = self.isRinging
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if let uuid = self.activeCallUUID, !self.isSimulatedCall {
                let endAction = CXEndCallAction(call: uuid)
                let transaction = CXTransaction(action: endAction)
                self.callController.request(transaction) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.statusNote = "Carrier calls decline via Bluetooth headset/intercom"
                            TripperDashClient.shared.log("ℹ️ iOS CallKit note: \(error.localizedDescription)")
                        }
                    }
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
            
            TripperDashClient.shared.sendCallAlert(
                callerName: caller,
                isRinging: true,
                isOngoing: false,
                durationSeconds: 0
            )
            TripperDashClient.shared.log("📞 Incoming call: '\(caller)' — Press Center/Up to Answer, Down to Decline")
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
        activeCallUUID = call.uuid
        isSimulatedCall = false
        
        if call.hasEnded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isRinging = false
                isOngoing = false
                statusNote = nil
            }
            stopCallTimer()
            TripperDashClient.shared.sendCallAlert(
                callerName: callerName,
                isRinging: false,
                isOngoing: false,
                durationSeconds: 0
            )
        } else if call.hasConnected {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isRinging = false
                isOngoing = true
                statusNote = nil
            }
            startCallTimer()
            detectConnectedAudioDevice()
            TripperDashClient.shared.sendCallAlert(
                callerName: callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: callDurationSeconds
            )
        } else if !call.isOutgoing {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isRinging = true
                isOngoing = false
                callerName = "Incoming Call"
                statusNote = nil
            }
            detectConnectedAudioDevice()
            TripperDashClient.shared.sendCallAlert(
                callerName: callerName,
                isRinging: true,
                isOngoing: false,
                durationSeconds: 0
            )
        }
    }
}
#endif
