"""Capture only a test process's visible client area, including mpv's idle/error OSD.
No media is loaded to obtain a screenshot. Uses the Windows desktop compositor,
not mpv's video-frame screenshot API, which needs a decoded video frame.
"""
from pathlib import Path
import ctypes as C
from ctypes import wintypes as W
import struct
import sys
import time
import zlib


def capture_client(pid: int, destination: Path) -> dict:
    if sys.platform != 'win32':
        raise RuntimeError('Window capture requires Windows')
    u = C.WinDLL('user32', use_last_error=True)
    g = C.WinDLL('gdi32', use_last_error=True)
    callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    u.EnumWindows.argtypes = [callback_type, W.LPARAM]
    u.EnumWindows.restype = W.BOOL
    u.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
    u.GetWindowThreadProcessId.restype = W.DWORD
    u.IsWindowVisible.argtypes = [W.HWND]
    u.IsWindowVisible.restype = W.BOOL
    u.GetClientRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
    u.GetClientRect.restype = W.BOOL
    u.ClientToScreen.argtypes = [W.HWND, C.POINTER(W.POINT)]
    u.ClientToScreen.restype = W.BOOL
    u.SetForegroundWindow.argtypes = [W.HWND]
    u.SetForegroundWindow.restype = W.BOOL
    u.SetWindowPos.argtypes = [W.HWND, W.HWND, C.c_int, C.c_int, C.c_int, C.c_int, W.UINT]
    u.SetWindowPos.restype = W.BOOL
    u.GetDC.argtypes = [W.HWND]
    u.GetDC.restype = W.HDC
    u.ReleaseDC.argtypes = [W.HWND, W.HDC]
    u.ReleaseDC.restype = C.c_int
    u.SetThreadDpiAwarenessContext.argtypes = [C.c_void_p]
    u.SetThreadDpiAwarenessContext.restype = C.c_void_p
    g.CreateCompatibleDC.argtypes = [W.HDC]
    g.CreateCompatibleDC.restype = W.HDC
    g.CreateCompatibleBitmap.argtypes = [W.HDC, C.c_int, C.c_int]
    g.CreateCompatibleBitmap.restype = W.HBITMAP
    g.SelectObject.argtypes = [W.HDC, C.c_void_p]
    g.SelectObject.restype = C.c_void_p
    g.BitBlt.argtypes = [W.HDC, C.c_int, C.c_int, C.c_int, C.c_int, W.HDC, C.c_int, C.c_int, W.DWORD]
    g.BitBlt.restype = W.BOOL
    g.GetDIBits.argtypes = [W.HDC, W.HBITMAP, W.UINT, W.UINT, C.c_void_p, C.c_void_p, W.UINT]
    g.GetDIBits.restype = C.c_int
    g.DeleteObject.argtypes = [C.c_void_p]
    g.DeleteObject.restype = W.BOOL
    g.DeleteDC.argtypes = [W.HDC]
    g.DeleteDC.restype = W.BOOL
    old_dpi = u.SetThreadDpiAwarenessContext(C.c_void_p(-4))
    desktop = memory = bitmap = previous = None
    try:
        windows = []
        @callback_type
        def visit(hwnd, _):
            owner = W.DWORD()
            u.GetWindowThreadProcessId(hwnd, C.byref(owner))
            r = W.RECT()
            if owner.value == pid and u.IsWindowVisible(hwnd) and u.GetClientRect(hwnd, C.byref(r)):
                width, height = r.right-r.left, r.bottom-r.top
                if width >= 64 and height >= 64:
                    windows.append((width*height, hwnd))
            return True
        if not u.EnumWindows(visit, 0) or not windows:
            raise RuntimeError('No visible client window for test process')
        hwnd = max(windows, key=lambda x: x[0])[1]
        u.SetWindowPos(hwnd, None, 0, 0, 0, 0, 0x0043)
        u.SetForegroundWindow(hwnd)
        time.sleep(.2)
        r, origin = W.RECT(), W.POINT()
        if not u.GetClientRect(hwnd, C.byref(r)) or not u.ClientToScreen(hwnd, C.byref(origin)):
            raise C.WinError(C.get_last_error())
        width, height = r.right-r.left, r.bottom-r.top
        if not (64 <= width <= 8192 and 64 <= height <= 8192):
            raise RuntimeError('Invalid client dimensions')
        desktop = u.GetDC(None)
        memory = g.CreateCompatibleDC(desktop)
        bitmap = g.CreateCompatibleBitmap(desktop, width, height)
        if not desktop or not memory or not bitmap:
            raise C.WinError(C.get_last_error())
        previous = g.SelectObject(memory, bitmap)
        if not g.BitBlt(memory, 0, 0, width, height, desktop, origin.x, origin.y, 0x40CC0020):
            raise C.WinError(C.get_last_error())
        g.SelectObject(memory, previous)
        previous = None
        header = C.create_string_buffer(struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 32, 0, width*height*4, 0, 0, 0, 0))
        pixels = C.create_string_buffer(width*height*4)
        if g.GetDIBits(memory, bitmap, 0, height, pixels, header, 0) != height:
            raise C.WinError(C.get_last_error())
        bgra = pixels.raw
        rgb = bytearray(width*height*3)
        rgb[0::3], rgb[1::3], rgb[2::3] = bgra[2::4], bgra[1::4], bgra[0::4]
        bright = sum(1 for v in rgb[0::3] if v > 180)
        if bright < 100 or len(set(rgb)) < 8:
            raise RuntimeError('Captured client has no visible controls or error text')
        def chunk(kind, body):
            return struct.pack('>I', len(body))+kind+body+struct.pack('>I', zlib.crc32(kind+body)&0xffffffff)
        scanlines = b''.join(b'\0'+rgb[y*width*3:(y+1)*width*3] for y in range(height))
        png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(scanlines))+chunk(b'IEND', b'')
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(png)
        return {'pid': pid, 'width': width, 'height': height, 'bright_pixels': bright}
    finally:
        if previous and memory:
            g.SelectObject(memory, previous)
        if bitmap:
            g.DeleteObject(bitmap)
        if memory:
            g.DeleteDC(memory)
        if desktop:
            u.ReleaseDC(None, desktop)
        if old_dpi:
            u.SetThreadDpiAwarenessContext(old_dpi)
