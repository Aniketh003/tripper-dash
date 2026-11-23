# Royal Enfield Tripper Dash & Pod Hardware Protocols

This document details the reverse-engineered network and BLE protocols required to connect directly to the physical instrument cluster on Royal Enfield motorcycles, replacing the stock companion app.

---

## 1. Royal Enfield Tripper Dash (Himalayan 450, Guerrilla 450, Bear 650 TFT)

The **Tripper Dash** is a round full-color TFT display manufactured by Visteon / Bosch for Royal Enfield's 450cc and 650cc platforms.

### Physical Architecture
The display has two independent interfaces:
1. **CAN Bus**: Connected to the bike's ECU (reads engine RPM, wheel speed, fuel level, gear position, telltales).
2. **Wi-Fi Subsystem**: The dash acts as a Wi-Fi Access Point (AP) for smartphone mirroring, navigation, and firmware updates.

```
┌─────────────────────────────────┐
│        Royal Enfield TFT        │
│          (Tripper Dash)         │
│          IP: 192.168.1.1        │
└──────┬───────────────────▲──────┘
       │ UDP/2002          │ UDP/5000
       │ (Control Plane)   │ (H.264 Video Stream)
       ▼                   │
┌──────────────────────────┴──────┐
│           iPhone App            │
│         (TripperDash)           │
│       Joined to Dash Wi-Fi      │
└─────────────────────────────────┘
```

### Network Topology & Handshake
- **Wi-Fi SSID Format**: `RE_XXXX_YYMMDD` (displayed on the dashboard under *Settings > Appearance > Screen Type > Digital*).
- **Default Wi-Fi Password**: `12345678`
- **Dash IP Address**: `192.168.1.1`
- **Control Port (UDP)**: `2002`
- **Video Stream Port (UDP)**: `5000`

### K1G Control Plane (UDP/2002)
The dash and phone exchange framed binary packets structured with standard command IDs and Type-Length-Value (TLV) payloads:

1. **Authentication Handshake (`0x07` command)**:
   - The phone sends an authentication frame containing an RSA-encrypted session key that includes the Dash Wi-Fi SSID.
   - The dash validates the key and replies with `0x07 0x01 0x01` (Success).
2. **Heartbeat / Keep-Alive (1 Hz Tick)**:
   - The phone must transmit a 1 Hz keep-alive packet over UDP port 2002. If the heartbeat stops for >3 seconds, the dash assumes connection drop and returns to the default analog/digital gauge screen.
3. **Navigation Mode Activation**:
   - The phone sends the Navigation Activation command (`q3c.z2` payload) telling the dash decoder to switch the display area to the H.264 video feed and bring up the turn maneuver overlay.
4. **Maneuver & Telemetry Cards**:
   - Packets containing:
     - Turn maneuver icon code (straight, left, right, roundabout exit, U-turn).
     - Distance to next maneuver (in meters or feet).
     - Road name / Destination label.
     - Phone battery percentage & GPS lock status.
5. **Joystick Input (Dash → Phone)**:
   - When the rider moves the left handlebar 5-way joystick (Up, Down, Left, Right, Center Click), the dash emits UDP packets on port 2002 to the phone.
   - Event bytes:
     - `0x01`: Left
     - `0x02`: Right
     - `0x03`: Down
     - `0x04`: Center Click / Enter

### Video Projection Stream (UDP/5000)
- **Container**: Raw RTP (Real-time Transport Protocol) payload.
- **Video Codec**: H.264 (AVC) Baseline Profile, Level 3.0.
- **Resolution**: 526 × 300 pixels (or circular masked canvas).
- **Frame Rate**: 4 fps to 12 fps (the embedded hardware decoder runs smoothly at 8–12 fps with ~300 kbps bitrate).
- **Max RTP Payload**: 1380 bytes per UDP packet (to prevent Wi-Fi MTU fragmentation).

---

## 2. Royal Enfield Tripper Pod (Meteor 350, Classic 350, Hunter 350 BLE)

The **Tripper Pod** is the secondary circular turn-by-turn navigation pod using Bluetooth Low Energy (BLE).

### BLE Specifications
- **BLE Device Name**: `RE_TRIPPER_XXXX`
- **GATT Service UUID**: `0000fee0-0000-1000-8000-00805f9b34fb` (or custom vendor UUID depending on firmware)
- **Data Characteristic (Write)**: `0000fee1-0000-1000-8000-00805f9b34fb`

### Packet Structure (20-byte chunks)
Each navigation update is packed into a 20-byte BLE packet:
```
[Byte 0]     : Packet Header / Command (0xA1 = Navigation Update)
[Byte 1]     : Turn Icon ID (0x01: Straight, 0x02: Slight Left, 0x03: Sharp Left, 0x04: Right, etc.)
[Byte 2..3]  : Distance to Next Turn (16-bit integer, in meters)
[Byte 4]     : Distance Unit (0 = meters, 1 = km, 2 = miles, 3 = ft)
[Byte 5]     : Progress Ring Fill Percentage (0 to 100)
[Byte 6..19] : Street / Highway Name (ASCII, truncated to 14 bytes)
```

### Auto-Reconnection
The app registers for CoreBluetooth state restoration so that whenever the bike's ignition is turned on, iOS automatically discovers and connects to the pod in the background without needing the rider to pull out their phone.
