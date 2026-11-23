import Foundation
#if os(iOS)
import CallKit
import AVFoundation
#endif

@Observable
public final class CallHandlingService: NSObject, @unchecked Sendable {
    public static let shared = CallHandlingService()
    
    public var isRinging: Bool = false
    public var isOngoing: Bool = false
    public var callerName: String = "Incoming Call"
    public var callDurationSeconds: UInt32 = 0
    public var activeAudioDeviceName: String = "iPhone"
    
    #if os(iOS)
    private let callObserver = CXCallObserver()
    private let callController = CXCallController()
    private var activeCallUUID: UUID?
    private var callTimer: Timer?
    #endif
    
    private override init() {
        super.init()
        #if os(iOS)
        callObserver.setDelegate(self, queue: .main)
        detectConnectedAudioDevice()
        #endif
    }
    
    #if os(iOS)
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
    #endif
    
    // MARK: - Handlebar & In-App Call Actions
    
    public func endOrRejectCall() {
        TripperDashClient.shared.log("📞 Call Rejected / Ended")
        
        #if os(iOS)
        if let uuid = activeCallUUID {
            let endAction = CXEndCallAction(call: uuid)
            let transaction = CXTransaction(action: endAction)
            callController.request(transaction) { error in
                if let error = error {
                    print("Notice: CXEndCallAction returned \(error)")
                }
            }
        }
        #endif
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRinging = false
            self.isOngoing = false
            #if os(iOS)
            self.callTimer?.invalidate()
            self.callTimer = nil
            #endif
            self.callDurationSeconds = 0
            
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: false,
                durationSeconds: 0
            )
        }
    }
    
    public func answerCall() {
        TripperDashClient.shared.log("📞 Call Answered via Handlebar / Cockpit")
        
        #if os(iOS)
        if let uuid = activeCallUUID {
            let answerAction = CXAnswerCallAction(call: uuid)
            let transaction = CXTransaction(action: answerAction)
            callController.request(transaction) { error in
                if let error = error {
                    print("Notice: CXAnswerCallAction returned \(error)")
                }
            }
        }
        #endif
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRinging = false
            self.isOngoing = true
            #if os(iOS)
            self.startCallTimer()
            self.detectConnectedAudioDevice()
            #endif
            
            TripperDashClient.shared.sendCallAlert(
                callerName: self.callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: 0
            )
        }
    }
    
    // MARK: - Simulated Call Trigger for Local Desk Testing
    
    public func simulateIncomingCall(caller: String = "John Doe (Mobile)") {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.callerName = caller
            self.isRinging = true
            self.isOngoing = false
            self.callDurationSeconds = 0
            self.detectConnectedAudioDevice()
            
            TripperDashClient.shared.sendCallAlert(
                callerName: caller,
                isRinging: true,
                isOngoing: false,
                durationSeconds: 0
            )
            TripperDashClient.shared.log("📞 [TEST] Incoming Call from: '\(caller)'")
            TripperDashClient.shared.log("👉 Press Center Click (or Up) to Answer, Down to Reject")
        }
    }
    
    // MARK: - Bluetooth Headset / Earphones Audio Route Detection
    
    public func detectConnectedAudioDevice() {
        #if os(iOS)
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                activeAudioDeviceName = output.portName // e.g. "Cardo Packtalk", "Sena 50S", "AirPods Pro"
                return
            }
        }
        activeAudioDeviceName = "Phone Speaker / Earpiece"
        #else
        activeAudioDeviceName = "Mac Speaker / Headphones"
        #endif
    }
}

#if os(iOS)
extension CallHandlingService: CXCallObserverDelegate {
    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        activeCallUUID = call.uuid
        
        if call.hasEnded {
            // Call Ended
            isRinging = false
            isOngoing = false
            callTimer?.invalidate()
            callTimer = nil
            callDurationSeconds = 0
            
            TripperDashClient.shared.sendCallAlert(
                callerName: callerName,
                isRinging: false,
                isOngoing: false,
                durationSeconds: 0
            )
        } else if call.hasConnected {
            // Call Ongoing
            isRinging = false
            isOngoing = true
            startCallTimer()
            detectConnectedAudioDevice()
            
            TripperDashClient.shared.sendCallAlert(
                callerName: callerName,
                isRinging: false,
                isOngoing: true,
                durationSeconds: callDurationSeconds
            )
        } else if !call.isOutgoing {
            // Incoming Call Ringing
            isRinging = true
            isOngoing = false
            callerName = "Incoming Call"
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
