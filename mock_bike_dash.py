#!/usr/bin/env python3
"""
Royal Enfield TFT Dash Simulator (K1G UDP Protocol)
Simulates the Himalayan 450 / Guerrilla 450 TFT Instrument Cluster locally.

Enables full desk testing of:
- UDP discovery & K1G RSA-1024 Handshake
- Live Turn-by-Turn Navigation & Route Cards
- Handlebar Joystick (Left, Right, Center Click, Down) via Mac keyboard
- Music Playback Info & Skip/Pause via Handlebar
- Incoming Call Alerts & Handlebar Answer/Reject
- 1Hz Background Heartbeat Telemetry
"""

import socket
import threading
import time
import sys
import os

# Precomputed 1024-bit RSA Public Key for K1G Handshake
RSA_MODULUS_HEX = (
    "c5e7d1c0695a28b60ec73ea3bee8ebf1987bd101cc1f98f63effddb4942a42ead648c4fe08801b2168"
    "2fe787cd1e44001cb5c351b10f8c174a4ceb078cf9465a1d89d8d561e5b02e0445bf86d0a34f1a9316"
    "b9d87709e6f43ce201ef8c5a10d7599d65ed49c7035cfcbe4ea9e66618a7dc8f7722cfbd6902827e54"
    "b46cf0c185"
)
RSA_EXPONENT_HEX = "010001"  # 65537

DASH_LISTEN_PORT = 2000
PHONE_LISTEN_PORT = 2002

class MockBikeDash:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("0.0.0.0", DASH_LISTEN_PORT))
        
        self.client_ip = None
        self.running = True
        self.is_authenticated = False
        
        # State display
        self.destination_title = "None"
        self.maneuver = "Straight"
        self.distance_turn = 0
        self.distance_total = 0
        self.music_title = "None"
        self.music_artist = "None"
        self.call_caller = "None"
        self.call_status = "IDLE ⚪"
        self.music_status = "IDLE ⚪"
        self.heartbeat_count = 0
        self.last_seen_time = time.time()
        
    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    def make_k1g_packet(self, seg_type, seg_sub, payload_bytes):
        seg_len = len(payload_bytes)
        seg = bytes([seg_type, seg_sub, (seg_len >> 8) & 0xFF, seg_len & 0xFF]) + payload_bytes
        total_len = len(seg) + 8
        hdr = bytes([ (total_len >> 8) & 0xFF, total_len & 0xFF, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 ])
        return hdr + seg

    def send_to_phone(self, data):
        if not self.client_ip:
            return
        try:
            self.sock.sendto(data, (self.client_ip, PHONE_LISTEN_PORT))
        except Exception as e:
            print(f"[Error sending to phone: {e}]")

    def handle_auth_request(self):
        print(f"\n🔐 [K1G] Received Handshake Request from iPhone ({self.client_ip})!")
        print("   -> Sending Dash RSA-1024 Public Key Modulus & Exponent...")
        
        # Send Modulus segment (07 00)
        mod_bytes = bytes.fromhex(RSA_MODULUS_HEX)
        pkt_mod = self.make_k1g_packet(0x07, 0x00, mod_bytes)
        self.send_to_phone(pkt_mod)
        time.sleep(0.02)
        
        # Send Exponent segment (07 03)
        exp_bytes = bytes.fromhex(RSA_EXPONENT_HEX)
        pkt_exp = self.make_k1g_packet(0x07, 0x03, exp_bytes)
        self.send_to_phone(pkt_exp)

    def handle_session_key(self, data):
        print(f"\n🔑 [K1G] Received Encrypted Session Key (q3c.d, {len(data)} bytes)!")
        print("   -> Sending Authentication OK (07 01 01)...")
        
        # Send Auth OK segment (07 01 01)
        pkt_ok = self.make_k1g_packet(0x07, 0x01, bytes([0x01]))
        self.send_to_phone(pkt_ok)
        self.is_authenticated = True
        print("   ✅ *** DASH AUTHENTICATION SUCCESSFUL! BIKE LINKED ***\n")

    def decode_packet(self, data):
        self.last_seen_time = time.time()
        if len(data) < 8:
            return
        
        hex_data = data.hex().upper()
        
        # 1. Check for initial auth request (q3c.e)
        if "0804000101" in hex_data or "4B3147" in hex_data and not self.is_authenticated:
            if "00950002" in hex_data or len(data) >= 140:
                self.handle_session_key(data)
            else:
                self.handle_auth_request()
            return
        
        # 2. Check for encrypted session key
        if "00950002" in hex_data and not self.is_authenticated:
            self.handle_session_key(data)
            return

        # 3. Handle Route Card packets (05 01 ...)
        if b"OpenDash" in data or "0501" in hex_data:
            idx = hex_data.find("0501")
            if idx != -1:
                try:
                    str_len = int(hex_data[idx+4:idx+8], 16)
                    start = (idx + 8) // 2
                    title_raw = data[start:start+str_len].split(b'\x00')[0]
                    self.destination_title = title_raw.decode('utf-8', errors='ignore')
                except Exception:
                    pass

        # 4. Handle Heartbeat (0044)
        if hex_data.startswith("0044"):
            self.heartbeat_count += 1

        # 5. Handle Maneuver (0502)
        if "05020001" in hex_data:
            idx = hex_data.find("05020001")
            m_code = int(hex_data[idx+8:idx+10], 16)
            maneuvers = {
                0x01: "Start", 0x02: "Continue", 0x03: "Turn Slight Right",
                0x04: "Turn Right", 0x05: "Turn Sharp Right", 0x06: "U-Turn",
                0x07: "Turn Sharp Left", 0x08: "Turn Left", 0x09: "Turn Slight Left",
                0x0B: "Navigation Active", 0x1B: "Roundabout", 0x1F: "Arrived at Destination"
            }
            self.maneuver = maneuvers.get(m_code, f"Maneuver 0x{m_code:02X}")
            
            # Next distance (05040002XXXX)
            if "05040002" in hex_data:
                d_idx = hex_data.find("05040002")
                self.distance_turn = int(hex_data[d_idx+8:d_idx+12], 16)
            # Total distance (05090002XXXX)
            if "05090002" in hex_data:
                t_idx = hex_data.find("05090002")
                self.distance_total = int(hex_data[t_idx+8:t_idx+12], 16)

        # 6. Handle Call State (05210001XX: 31 = Ringing, 32 = Ongoing, 30 = Idle)
        if "05210001" in hex_data:
            idx = hex_data.find("05210001")
            status_code = hex_data[idx+8:idx+10]
            if status_code == "31":
                self.call_status = "RINGING 📞"
            elif status_code == "32":
                self.call_status = "ONGOING 🟢"
            else:
                self.call_status = "IDLE ⚪"

        # 7. Handle Music Play/Pause (054C0001XX: 18 = Playing, 10/15 = Paused)
        if "054C0001" in hex_data:
            idx = hex_data.find("054C0001")
            m_vol = hex_data[idx+8:idx+10]
            self.music_status = "PLAYING ▶️" if m_vol == "18" else "PAUSED ⏸️"

    def send_joystick(self, byte_val, name):
        """Sends handlebar joystick event to phone on port 2002."""
        if not self.client_ip:
            print("⚠️ Cannot send joystick event: No phone connected yet!")
            return
        pkt = self.make_k1g_packet(0x09, 0x00, bytes([byte_val]))
        self.send_to_phone(pkt)
        print(f"🎮 [Handlebar] Sent Joystick '{name}' (0x{byte_val:02X}) to {self.client_ip}:2002")

    def rx_loop(self):
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                self.client_ip = addr[0]
                self.decode_packet(data)
            except Exception:
                break

    def display_loop(self):
        while self.running:
            time.sleep(1.0)
            if not self.is_authenticated:
                continue
            
            status_text = f"LINKED ({self.client_ip})" if (time.time() - self.last_seen_time < 4) else "DISCONNECTED"
            line = (
                f"\r\033[K🏍️  [TFT DASH] {status_text} | Call: {self.call_status} | Music: {self.music_status} | "
                f"Dest: {self.destination_title[:15]} | Heartbeats: {self.heartbeat_count}"
            )
            try:
                term_cols = os.get_terminal_size().columns
                if len(line) - 5 > term_cols:
                    line = line[:term_cols + 4]
            except Exception:
                pass
            sys.stdout.write(line)
            sys.stdout.flush()

    def run(self):
        local_ip = self.get_local_ip()
        print("=" * 68)
        print("      ROYAL ENFIELD TFT DASH SIMULATOR (HIMALAYAN 450 K1G)      ")
        print("=" * 68)
        print(f"  📡 Mock Bike Listening on : 0.0.0.0:{DASH_LISTEN_PORT}")
        print(f"  💻 Mac Wi-Fi IP Address   : {local_ip}")
        print(f"  📱 Enter this IP in App   : {local_ip}")
        print("=" * 68)
        print("  Instructions:")
        print(f"  1. Ensure your iPhone & Mac are on the same Wi-Fi.")
        print(f"  2. In TripperDash on iPhone -> Settings tab:")
        print(f"     Set 'Dash IP' to: {local_ip}")
        print(f"  3. Tap 'Connect' in the app.")
        print("=" * 68)
        print("  Handlebar Controls (Type letter & press Enter):")
        print("    [r]    Right        -> Next Music Track")
        print("    [l]    Left         -> Previous Music Track")
        print("    [c]    Center Click -> Play / Pause (or Answer incoming call)")
        print("    [u]    Up           -> Volume UP (or Answer incoming call)")
        print("    [d]    Down         -> Volume DOWN (or Reject / End call)")
        print("    [call] Test Call    -> Trigger simulated incoming call on phone")
        print("    [q]    Quit")
        print("=" * 68)
        print("Waiting for iPhone connection...\n")

        t_rx = threading.Thread(target=self.rx_loop, daemon=True)
        t_rx.start()

        t_disp = threading.Thread(target=self.display_loop, daemon=True)
        t_disp.start()

        while self.running:
            try:
                cmd = input().strip().lower()
                if cmd == 'q':
                    print("\nExiting simulator...")
                    self.running = False
                    break
                elif cmd == 'r':
                    self.send_joystick(0x13, "RIGHT (Next Track)")
                elif cmd == 'l':
                    self.send_joystick(0x14, "LEFT (Prev Track)")
                elif cmd == 'c':
                    self.send_joystick(0x18, "CENTER (Play/Pause/Answer)")
                elif cmd == 'd':
                    self.send_joystick(0x15, "DOWN (Vol Down / End Call)")
                elif cmd == 'u':
                    self.send_joystick(0x05, "UP (Vol Up / Answer Call)")
                elif cmd == 'call':
                    self.send_joystick(0xFE, "SIMULATE INCOMING CALL")
                    print("📞 [Simulator] Triggered incoming call on iPhone from 'Royal Enfield Support'!")
                elif cmd == '':
                    pass
                else:
                    print(f"Unknown command '{cmd}'. Available: [r], [l], [c], [u], [d], [call], [q]")
            except (KeyboardInterrupt, EOFError):
                break

        self.running = False
        self.sock.close()

if __name__ == "__main__":
    dash = MockBikeDash()
    dash.run()
