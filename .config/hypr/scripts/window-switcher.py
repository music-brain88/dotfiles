#!/usr/bin/env python3

import json
import subprocess
import sys
from typing import List, Dict

def get_windows() -> List[Dict]:
    """Get list of all windows"""
    try:
        result = subprocess.run(
            ['hyprctl', 'clients', '-j'],
            capture_output=True,
            text=True
        )
        windows = json.loads(result.stdout)
        # マップされているウィンドウのみをフィルタリング
        return [w for w in windows if w.get('mapped', False)]
    except (subprocess.SubprocessError, json.JSONDecodeError) as e:
        print(f"Error getting windows: {e}", file=sys.stderr)
        return []

def get_active_window_address() -> str:
    """Get the address of the currently active window"""
    try:
        result = subprocess.run(
            ['hyprctl', 'activewindow', '-j'],
            capture_output=True,
            text=True
        )
        active = json.loads(result.stdout)
        return active.get('address', '')
    except (subprocess.SubprocessError, json.JSONDecodeError):
        return ''

def focus_window(address: str):
    """Focus the window with the given address"""
    try:
        subprocess.run(['hyprctl', 'dispatch', 'focuswindow', f"address:{address}"])
    except subprocess.SubprocessError as e:
        print(f"Error focusing window: {e}", file=sys.stderr)

def main():
    # Get all windows
    windows = get_windows()
    if not windows:
        return 1

    # Get current active window
    current = get_active_window_address()
    
    # Find current window index
    current_index = 0
    for i, window in enumerate(windows):
        if window.get('address') == current:
            current_index = i
            break

    # Determine direction
    reverse = len(sys.argv) > 1 and sys.argv[1] == "reverse"
    
    # Calculate next window index
    if reverse:
        next_index = (current_index - 1) % len(windows)
    else:
        next_index = (current_index + 1) % len(windows)

    # Focus next window
    next_window = windows[next_index]
    focus_window(next_window['address'])
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
