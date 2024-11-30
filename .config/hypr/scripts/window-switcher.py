#!/usr/bin/env python3

import json
import subprocess
import sys
import os
import socket
import selectors
import struct
import time
from typing import List, Dict, Optional, Set

class HyprlandWindow:
    def __init__(self, window_data: Dict):
        self.id = window_data.get('address')
        self.workspace = window_data.get('workspace', {}).get('id', 0)
        self.title = window_data.get('title', 'Unknown')
        self.class_name = window_data.get('class', 'Unknown')
        self.is_focused = window_data.get('focused', False)

class HyprlandEventHandler:
    def __init__(self):
        self.sock_path = f"/tmp/hypr/{os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')}/.socket2.sock"
        self.sel = selectors.DefaultSelector()
        self._setup_socket()
        self.alt_pressed = True
        self.tab_pressed = False

    def _setup_socket(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.sock_path)
        self.sock.setblocking(False)
        self.sel.register(self.sock, selectors.EVENT_READ)

    def read_event(self, timeout: float = 0.1) -> Optional[str]:
        events = self.sel.select(timeout)
        for key, _ in events:
            try:
                data = key.fileobj.recv(4096).decode()
                if data:
                    return data.strip()
            except (socket.error, UnicodeDecodeError):
                return None
        return None

    def wait_for_alt_release(self) -> bool:
        while True:
            event = self.read_event()
            if event:
                event_parts = event.split(">>")
                if len(event_parts) >= 2:
                    event_type = event_parts[0]
                    event_data = event_parts[1]

                    if event_type == "keyrelease":
                        # Alt_L のキーコードは 64
                        if "64" in event_data:
                            return False
                    elif event_type == "keypress":
                        # Tab のキーコードは 23
                        if "23" in event_data:
                            return True
            time.sleep(0.01)

class WindowManager:
    def __init__(self):
        self.windows: List[HyprlandWindow] = []
        self.load_windows()
        self.current_index = self.get_focused_window_index()

    def load_windows(self):
        try:
            result = subprocess.run(
                ['hyprctl', 'clients', '-j'],
                capture_output=True,
                text=True
            )
            windows_data = json.loads(result.stdout)
            # マップされているウィンドウのみを対象にする
            self.windows = [HyprlandWindow(w) for w in windows_data if w.get('mapped', False)]
        except (subprocess.SubprocessError, json.JSONDecodeError) as e:
            print(f"Error loading windows: {e}", file=sys.stderr)
            self.windows = []

    def get_focused_window_index(self) -> int:
        for i, window in enumerate(self.windows):
            if window.is_focused:
                return i
        return 0

    def focus_next_window(self, reverse: bool = False):
        if not self.windows:
            return

        if reverse:
            self.current_index = (self.current_index - 1) % len(self.windows)
        else:
            self.current_index = (self.current_index + 1) % len(self.windows)

        window = self.windows[self.current_index]
        self.focus_window(window.id)

    def focus_window(self, window_id: str):
        try:
            subprocess.run(['hyprctl', 'dispatch', 'focuswindow', f"address:{window_id}"])
        except subprocess.SubprocessError as e:
            print(f"Error focusing window: {e}", file=sys.stderr)

def main():
    wm = WindowManager()
    event_handler = HyprlandEventHandler()
    reverse = len(sys.argv) > 1 and sys.argv[1] == "reverse"

    # 最初のウィンドウ切り替え
    wm.focus_next_window(reverse)

    # Altキーが離されるまでTabキーの入力を監視
    while event_handler.wait_for_alt_release():
        wm.focus_next_window(reverse)

if __name__ == '__main__':
    sys.exit(main())
