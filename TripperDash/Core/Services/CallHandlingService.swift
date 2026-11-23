import Foundation
import CallKit
import AVFoundation

@Observable
public final class CallHandlingService: NSObject, CXCallObserverDelegate, @unchecked Sendable {
    public static let shared = CallHandlingService()
    
    public var isRinging: Bool = false
    public var isOngoing: Bool = false
    public var callerName: String = "Incoming Call"
    public var callDurationSeconds: UInt32 = 0
    public var activeAudioDeviceName: String = "iPhone"
    
    private let callObserver = CXCallObserver()
    private let callController = CXCallController()
    private var activeCallUUID: UUID?
    private var callTimer: Timer?
    
    private override init() {
        super.init()
        callObserver.setDelegate(self, queue: .main)
        detectConnectedAudioDevice()
    }
    
    // MARK: - CXCallObserverDelegate
    
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
    
    // MARK: - Handlebar & In-App Call Actions
    
    public func endOrRejectCall() {
        guard let uuid = activeCallUUID else { return }
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Failed to end call: \(error)")
            }
        }
    }
    
    public func answerCall() {
        guard let uuid = activeCallUUID else { return }
        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerAction)
        
        callController.request(transaction) { [weak self] error in
            if error == nil {
                self?.isRinging = false
                self?.isOngoing = true
                self?.detectConnectedAudioDevice()
            }
        }
    }
    
    // MARK: - Bluetooth Headset / Earphones Audio Route Detection
    
    public func detectConnectedAudioDevice() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                activeAudioDeviceName = output.portName // e.g. "Cardo Packtalk", "Sena 50S", "AirPods Pro"
                return
            }
        }
        activeAudioDeviceName = "Phone Speaker / Earpiece"
    }
}
