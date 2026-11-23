#!/usr/bin/env python3
"""
Royal Enfield Himalayan 450 TFT Digital Dash Simulator (K1G UDP + RTP Video)
Simulates both:
  - UDP/2000 & 2002: K1G Control Plane (RSA Handshake, Homescreen Banner, Weather, Music, Volume, Calls, Joystick)
  - UDP/5000: H.264 RTP Video Projection Receiver (verifies live Digital Homescreen frames & FPS)
"""

import socket
import threading
import time
import sys
import os

RSA_MODULUS_HEX = (
    "c5e7d1c0695a28b60ec73ea3bee8ebf1987bd101cc1f98f63effddb4942a42ead648c4fe08801b2168"
    "2fe787cd1e44001cb5c351b10f8c174a4ceb078cf9465a1d89d8d561e5b02e0445bf86d0a34f1a9316"
    "b9d87709e6f43ce201ef8c5a10d7599d65ed49c7035cfcbe4ea9e66618a7dc8f7722cfbd6902827e54"
    "b46cf0c185"
)
RSA_EXPONENT_HEX = "010001"

DASH_LISTEN_PORT = 2000
PHONE_LISTEN_PORT = 2002
VIDEO_RTP_PORT = 5000


class MockBikeDash:
    def __init__(self):
        # K1G Control UDP Socket (Port 2000)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("0.0.0.0", DASH_LISTEN_PORT))

        # H.264 RTP Video Projection Socket (Port 5000)
        self.video_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.video_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.video_sock.bind(("0.0.0.0", VIDEO_RTP_PORT))

        self.client_ip = None
        self.running = True
        self.is_authenticated = False

        # Live TFT Digital Homescreen State
        self.homescreen_banner = "Standby"
        self.weather_summary = "Waiting for GPS..."
        self.temp_c = 25
        self.battery_pct = 100
        self.music_title = "Not Playing"
        self.music_artist = ""
        self.music_playing = False
        self.volume_pct = 50
        self.call_state = "IDLE"
        self.caller_name = ""
        self.call_duration = 0
        self.heartbeat_count = 0
        self.video_packets = 0
        self.video_frames = 0
        self.video_fps = 0.0
        self._last_fps_ts = time.time()
        self._frames_in_window = 0
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
        hdr = bytes([(total_len >> 8) & 0xFF, total_len & 0xFF, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
        return hdr + seg

    def send_to_phone(self, data):
        if not self.client_ip:
            return
        try:
            self.sock.sendto(data, (self.client_ip, PHONE_LISTEN_PORT))
        except Exception as e:
            print(f"\n[Error sending to phone: {e}]")

    def handle_auth_request(self):
        print(f"\n🔐 [K1G] Handshake Request from iPhone ({self.client_ip})")
        print("   → Sending Dash RSA-1024 Public Key...")
        self.send_to_phone(self.make_k1g_packet(0x07, 0x00, bytes.fromhex(RSA_MODULUS_HEX)))
        time.sleep(0.02)
        self.send_to_phone(self.make_k1g_packet(0x07, 0x03, bytes.fromhex(RSA_EXPONENT_HEX)))

    def handle_session_key(self, data):
        print(f"🔑 [K1G] Received Encrypted Session Key ({len(data)} B) → Sending Auth OK (07 01 01)")
        self.send_to_phone(self.make_k1g_packet(0x07, 0x01, bytes([0x01])))
        self.is_authenticated = True
        print("✅ *** HIMALAYAN 450 TFT CONNECTED ***\n")

    def parse_tlvs(self, data):
        """Parses standard K1G TLV segments starting at byte offset 8."""
        if len(data) < 8:
            return []
        seg_count = (data[2] << 8) | data[3]
        offset = 8
        tlvs = []
        for _ in range(seg_count):
            if offset + 4 > len(data):
                break
            t = data[offset]
            sub = data[offset + 1]
            slen = (data[offset + 2] << 8) | data[offset + 3]
            offset += 4
            payload = data[offset : offset + slen]
            offset += slen
            tlvs.append((t, sub, payload))
        return tlvs

    def decode_packet(self, data):
        self.last_seen_time = time.time()
        if len(data) < 8:
            return

        hex_data = data.hex().upper()

        # Handshake detection
        if not self.is_authenticated:
            if "00950002" in hex_data or len(data) >= 140:
                self.handle_session_key(data)
                return
            if "0804000101" in hex_data or "4B3147" in hex_data:
                self.handle_auth_request()
                return

        if hex_data.startswith("0044"):
            self.heartbeat_count += 1

        # Decode every structured TLV cleanly
        for t, sub, payload in self.parse_tlvs(data):
            if t == 0x05 and sub == 0x01:
                # TFT Digital Homescreen Banner / Destination
                txt = payload.split(b"\x00")[0].decode("utf-8", errors="ignore").strip()
                if txt:
                    self.homescreen_banner = txt
            elif t == 0x05 and sub == 0x4C and len(payload) >= 1:
                self.music_playing = (payload[0] == 0x18)
            elif t == 0x05 and sub == 0x4E:
                self.music_title = payload.split(b"\x00")[0].decode("utf-8", errors="ignore").strip() or "Not Playing"
            elif t == 0x05 and sub == 0x4F:
                self.music_artist = payload.split(b"\x00")[0].decode("utf-8", errors="ignore").strip()
            elif t == 0x05 and sub == 0x50 and len(payload) >= 1:
                self.volume_pct = payload[0]
            elif t == 0x05 and sub == 0x51:
                self.weather_summary = payload.split(b"\x00")[0].decode("utf-8", errors="ignore").strip()
            elif t == 0x06 and sub == 0x10 and len(payload) >= 1:
                self.temp_c = payload[0] - 40
            elif t == 0x06 and sub == 0x04 and len(payload) >= 1:
                self.battery_pct = max(0, min(100, payload[0] - 100))
            elif t == 0x05 and sub == 0x21 and len(payload) >= 1:
                code = payload[0]
                if code == 0x31:
                    self.call_state = "RINGING 📞"
                elif code == 0x32:
                    self.call_state = "ONGOING 🟢"
                else:
                    self.call_state = "IDLE"
                    self.call_duration = 0
            elif t == 0x05 and sub == 0x22:
                self.caller_name = payload.split(b"\x00")[0].decode("utf-8", errors="ignore").strip()
            elif t == 0x05 and sub == 0x23 and len(payload) >= 2:
                self.call_duration = (payload[0] << 8) | payload[1]

    def send_joystick(self, byte_val, name):
        if not self.client_ip:
            print("⚠️  No iPhone connected yet! Enter this Mac's IP in Settings and tap Connect.")
            return
        pkt = self.make_k1g_packet(0x09, 0x00, bytes([byte_val]))
        self.send_to_phone(pkt)
        print(f"\n🎮 [Joystick → iPhone] {name} (0x{byte_val:02X})")

    def rx_loop(self):
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                self.client_ip = addr[0]
                self.decode_packet(data)
            except Exception:
                break

    def video_rx_loop(self):
        while self.running:
            try:
                data, _ = self.video_sock.recvfrom(65535)
                self.video_packets += 1
                # RTP marker bit (byte 1 bit 7) indicates end of an encoded H.264 video frame
                if len(data) >= 12 and (data[1] & 0x80):
                    self.video_frames += 1
                    self._frames_in_window += 1
                    now = time.time()
                    elapsed = now - self._last_fps_ts
                    if elapsed >= 2.0:
                        self.video_fps = self._frames_in_window / elapsed
                        self._frames_in_window = 0
                        self._last_fps_ts = now
            except Exception:
                break

    def display_loop(self):
        while self.running:
            time.sleep(1.0)
            if not self.is_authenticated:
                continue

            call_str = self.call_state
            if self.call_state.startswith("ONGOING"):
                mins, secs = divmod(self.call_duration, 60)
                call_str = f"ONGOING {mins:02d}:{secs:02d} ({self.caller_name})"
            elif self.call_state.startswith("RINGING"):
                call_str = f"RINGING ({self.caller_name})"

            music_icon = "▶️" if self.music_playing else "⏸️"
            song_str = f"{music_icon} {self.music_title}" + (f" - {self.music_artist}" if self.music_artist else "")
            video_str = f"{self.video_fps:.1f}fps" if self.video_packets > 0 else "off"

            line = (
                f"\r\033[K🏍️  [TFT] {self.weather_summary} | "
                f"{song_str[:24]} | Vol {self.volume_pct}% | "
                f"Call: {call_str} | H264: {video_str} | Bat {self.battery_pct}%"
            )
            try:
                cols = os.get_terminal_size().columns
                if len(line) - 6 > cols:
                    line = line[: cols + 3]
            except Exception:
                pass
            sys.stdout.write(line)
            sys.stdout.flush()

    def run(self):
        local_ip = self.get_local_ip()
        print("=" * 72)
        print("      ROYAL ENFIELD HIMALAYAN 450 TFT DIGITAL DASH SIMULATOR      ")
        print("=" * 72)
        print(f"  📡 Control Port : UDP/{DASH_LISTEN_PORT}   |   📺 Video Stream : UDP/{VIDEO_RTP_PORT}")
        print(f"  💻 Mac Wi-Fi IP : {local_ip}")
        print(f"  📱 In iPhone App → Settings → Dash Host IP = {local_ip} → Connect")
        print("=" * 72)
        print("  Handlebar Joystick Controls (type command & press Enter):")
        print("    [u]    Joystick UP     → Volume UP   (or Answer Ringing Call)")
        print("    [d]    Joystick DOWN   → Volume DOWN (or Decline / End Call)")
        print("    [c]    Center Click    → Play/Pause  (or Answer / End Call)")
        print("    [r]    Joystick RIGHT  → Next Track")
        print("    [l]    Joystick LEFT   → Previous Track")
        print("    [call] Simulate Call   → Ring iPhone to test Answer & Drop")
        print("    [q]    Quit")
        print("=" * 72)
        print("Waiting for iPhone connection...\n")

        threading.Thread(target=self.rx_loop, daemon=True).start()
        threading.Thread(target=self.video_rx_loop, daemon=True).start()
        threading.Thread(target=self.display_loop, daemon=True).start()

        while self.running:
            try:
                cmd = input().strip().lower()
                if cmd == "q":
                    print("\nExiting TFT Simulator...")
                    self.running = False
                    break
                elif cmd == "u":
                    self.send_joystick(0x05, "UP (Vol + / Answer)")
                elif cmd == "d":
                    self.send_joystick(0x15, "DOWN (Vol - / Decline or End Call)")
                elif cmd == "c":
                    self.send_joystick(0x18, "CENTER (Play/Pause / Answer or End Call)")
                elif cmd == "r":
                    self.send_joystick(0x13, "RIGHT (Next Track)")
                elif cmd == "l":
                    self.send_joystick(0x14, "LEFT (Previous Track)")
                elif cmd == "call":
                    self.send_joystick(0xFE, "SIMULATE INCOMING CALL")
                elif cmd == "":
                    pass
                else:
                    print(f"\nUnknown command '{cmd}'. Use: u, d, c, r, l, call, q")
            except (KeyboardInterrupt, EOFError):
                break

        self.running = False
        self.sock.close()
        self.video_sock.close()


if __name__ == "__main__":
    MockBikeDash().run()
