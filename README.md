# TripperDash (iOS)

Minimalist, fluid, native iOS companion and instrument hub for motorcycles (specifically Royal Enfield Himalayan 450, Guerrilla 450, Bear 650, Hunter 350, Meteor 350, and Classic 350).

Ported from [OpenDash](https://github.com/subtlesayak/open-dash) to **Swift & SwiftUI** with a high-performance OLED cockpit design and reverse-engineered physical dash communication protocols.

---

## Features

- **Minimalist Cockpit**: 120Hz smooth circular speedometer, compass heading, real-time altitude, and continuous ride tracker.
- **Garage & Maintenance**: Multi-vehicle profiles, ODO tracking, 5,000 km service milestone countdown, spare parts inventory, and maintenance logs.
- **Ownership Expenses**: Category pills (Fuel, Repairs, Gear, Stays, Food), monthly totals, and instant CSV export to Files/AirDrop.
- **Route Preview**: Paste Google Maps links or coordinates, preview turns on interactive Apple Maps, and transmit maneuver steps to the bike.
- **Ride Recording**: Background GPS tracking with stationary noise filtering, recording top speed, average speed, moving time, and full polyline route history.
- **Physical Bike Link**:
  - **Tripper Dash (Himalayan 450 TFT)**: K1G protocol over UDP (heartbeat, turn-by-turn cards, and handlebar joystick input).
  - **Tripper Pod (Classic/Meteor/Hunter 350)**: CoreBluetooth BLE client pushing 20-byte navigation updates.
- **Firebase Sync**: Ready for cloud backups and Firestore cross-device sync.

---

## Project Structure

```
tripper-dash/
├── DASH_PROTOCOL.md            # Complete reverse-engineered protocol documentation
├── TripperDash.xcodeproj/       # Xcode project ready to open on Mac
├── Package.swift               # Swift Package Manager manifest
└── TripperDash/
    ├── Info.plist              # Background location & Bluetooth permissions
    ├── App/
    │   ├── TripperDashApp.swift# App entry point with OLED theme styling
    │   └── AppState.swift      # Central state container
    ├── Core/
    │   ├── Theme/              # Minimalist OLED palette & high-performance components
    │   ├── Location/           # Continuous background CoreLocation ride tracker
    │   └── Network/            # Google polyline encoder/decoder & MapKit directions
    ├── Data/
    │   ├── Models/             # Vehicle, Expense, GarageLog, and Ride models
    │   ├── Persistence/        # Thread-safe local storage & vehicle profile store
    │   └── Sync/               # Firebase sync manager & config template
    ├── DashProtocol/
    │   ├── TFTDash/            # K1G UDP packet builder & TripperDashClient
    │   └── TripperPod/         # CoreBluetooth TripperPodClient
    └── Features/
        ├── Cockpit/            # Live speedometer gauge & session recorder
        ├── Garage/             # Bike switcher, service countdown, maintenance log
        ├── Expenses/           # Expense tracking with category filters & CSV export
        ├── Routes/             # Destination parser, route preview & turn cards
        ├── Rides/              # History list & route polyline viewer
        └── Settings/           # Firebase connection, Dash Wi-Fi/BLE controls
```

---

## Setup on Mac & Installing to Your iPhone

### 1. Clone or Pull the Repo
```bash
git clone https://github.com/Aniketh003/tripper-dash.git
cd tripper-dash
```

### 2. Connect Your Firebase Account
1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Select or create your project.
3. Add an **iOS App** with Bundle ID: `com.opendash.tripperdash`.
4. Download `GoogleService-Info.plist` and place it in `TripperDash/Data/Sync/` (replacing the template).

### 3. Open in Xcode
Double-click `TripperDash.xcodeproj` or run:
```bash
open TripperDash.xcodeproj
```

### 4. Sideload to Your iPhone (Without App Store)
1. Connect your iPhone to your Mac via USB.
2. In Xcode, select the **TripperDash** target > **Signing & Capabilities**.
3. Under **Team**, select your personal Apple ID (*Personal Team*).
4. On your iPhone:
   - Go to **Settings > Privacy & Security > Developer Mode** and switch it **ON** (your iPhone will restart).
5. In Xcode, select your iPhone as the run target at the top and press **Cmd + R** (Run).
6. On your iPhone:
   - Go to **Settings > General > VPN & Device Management**, tap your developer certificate, and tap **Trust**.
7. The app is now installed and ready to test on your bike!

---

## Connecting to Your Motorcycle

Refer to [`DASH_PROTOCOL.md`](DASH_PROTOCOL.md) for full details on:
- Connecting to the Himalayan 450 TFT display Wi-Fi (`RE_xxxx_yymmdd`).
- Pairing with the Tripper Pod via Bluetooth Low Energy.