#!/usr/bin/env python3

import json
import subprocess
import sys
import os
import tempfile
from typing import List, Dict

class WindowPreview:
    def __init__(self):
        self.temp_dir = tempfile.mkdtemp()
        self.preview_file = os.path.join(self.temp_dir, "window_preview.png")
        
    def capture_window(self, window_address: str) -> str:
        """Capture window preview using grimblast"""
        try:
            subprocess.run([
                'hyprctl', 'dispatch', 'focuswindow', f"address:{window_address}"
            ])
            # Give the window a moment to focus
            subprocess.run(['sleep', '0.1'])
            # Capture the window
            subprocess.run([
                'grimblast', 'save', 'active', self.preview_file
            ])
            return self.preview_file
        except subprocess.SubprocessError as e:
            print(f"Error capturing window: {e}", file=sys.stderr)
            return ""

    def cleanup(self):
        """Clean up temporary files"""
        try:
            os.remove(self.preview_file)
            os.rmdir(self.temp_dir)
        except OSError:
            pass

def get_windows() -> List[Dict]:
    """Get list of all windows"""
    try:
        result = subprocess.run(
            ['hyprctl', 'clients', '-j'],
            capture_output=True,
            text=True
        )
        windows = json.loads(result.stdout)
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

def show_preview_window(windows: List[Dict], current_index: int):
    """Show preview window using eww"""
    current_window = windows[current_index]
    
    # Generate preview image
    preview = WindowPreview()
    preview_path = preview.capture_window(current_window['address'])
    
    # Create eww widget content
    window_data = {
        "windows": [
            {
                "title": w['title'],
                "class": w['class'],
                "active": i == current_index,
                "workspace": w.get('workspace', {}).get('id', 1)
            } for i, w in enumerate(windows)
        ],
        "current": {
            "title": current_window['title'],
            "class": current_window['class'],
            "preview": preview_path
        }
    }
    
    # Save window data to temporary file
    data_file = os.path.join(preview.temp_dir, "window_data.json")
    with open(data_file, 'w') as f:
        json.dump(window_data, f)
    
    # Update eww variables
    subprocess.run(['eww', 'update', f"window_data={data_file}"])
    
    # Show eww window
    subprocess.run(['eww', 'open', 'window_switcher'])
    
    return preview

def close_preview_window(preview: WindowPreview):
    """Close preview window and clean up"""
    subprocess.run(['eww', 'close', 'window_switcher'])
    preview.cleanup()

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

    # Show preview window
    preview = show_preview_window(windows, next_index)
    
    # Focus next window
    next_window = windows[next_index]
    focus_window(next_window['address'])

    # Wait a moment before closing preview
    subprocess.run(['sleep', '0.5'])
    close_preview_window(preview)
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
