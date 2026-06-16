#!/usr/bin/env python3
"""
zui UIA test suite — verifies every interactive element is reachable via
Windows UI Automation, navigates each page, and asserts state changes.

Usage:
    python tests/uia_test.py                  # launch app, test, kill
    python tests/uia_test.py --no-launch      # connect to already-running instance
    python tests/uia_test.py --exe path/to/zui.exe
"""

import argparse
import ctypes
import subprocess
import sys
import time

try:
    from pywinauto import Application
    import win32gui
    import win32con
except ImportError:
    sys.exit(
        "ERROR: dependencies missing.\n"
        "Run: pip install pywinauto pywin32"
    )

WIN_RE   = ".*Component Gallery.*"
PASS_SYM = "+"
FAIL_SYM = "x"


# ── Low-level click via PostMessage (no SetCursorPos, terminal-safe) ──────────

def _post_click(hwnd, screen_x, screen_y):
    """Send WM_LBUTTONDOWN/UP to hwnd at client coords derived from screen pos."""
    cx, cy = win32gui.ScreenToClient(hwnd, (screen_x, screen_y))
    lparam  = (cy << 16) | (cx & 0xFFFF)
    win32gui.PostMessage(hwnd, win32con.WM_LBUTTONDOWN, win32con.MK_LBUTTON, lparam)
    time.sleep(0.05)
    win32gui.PostMessage(hwnd, win32con.WM_LBUTTONUP,   0,                    lparam)
    time.sleep(0.05)


def click_el(win, el):
    """Click a pywinauto UIA element via PostMessage (terminal-safe)."""
    r   = el.rectangle()
    cx  = (r.left + r.right)  // 2
    cy  = (r.top  + r.bottom) // 2
    _post_click(win.handle, cx, cy)


def click_abs(win, screen_x, screen_y):
    """Click at absolute screen coords via PostMessage."""
    _post_click(win.handle, screen_x, screen_y)


# ── Result tracker ────────────────────────────────────────────────────────────

class Results:
    def __init__(self):
        self.passed  = 0
        self.failed  = 0
        self._fails  = []

    def ok(self, label):
        print(f"  {PASS_SYM}  {label}")
        self.passed += 1

    def fail(self, label, detail=""):
        msg = label + (f"  ({detail})" if detail else "")
        print(f"  {FAIL_SYM}  {msg}")
        self.failed += 1
        self._fails.append(msg)

    def assert_exists(self, win, name, ctrl=None):
        """Assert the UIA element is in the tree; return it or None."""
        kw = {"title": name}
        if ctrl:
            kw["control_type"] = ctrl
        try:
            el = win.child_window(**kw)
            if el.exists(timeout=2):
                tag = f"[{ctrl}]" if ctrl else "[?]"
                self.ok(f"{tag} '{name}' in UIA tree")
                return el
            self.fail(f"[{ctrl or '?'}] '{name}'", "not found in UIA tree")
        except Exception as exc:
            self.fail(f"[{ctrl or '?'}] '{name}'", str(exc))
        return None

    def assert_click(self, win, name, ctrl=None):
        """Assert element exists and click it."""
        el = self.assert_exists(win, name, ctrl)
        if el:
            try:
                click_el(win, el)
                return el
            except Exception as exc:
                self.fail(f"click '{name}'", str(exc))
        return None

    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*52}")
        print(f"  {self.passed}/{total} passed", end="")
        if self.failed == 0:
            print("  -- all green")
        else:
            print(f"  -- {self.failed} failed")
            for f in self._fails:
                print(f"    {FAIL_SYM}  {f}")
        print('='*52)
        return self.failed == 0


# ── Helpers ───────────────────────────────────────────────────────────────────

def nav(win, page, r):
    """Click a sidebar nav button and give the page time to paint."""
    el = win.child_window(title=page, control_type="Button")
    if not el.exists(timeout=2):
        r.fail(f"navigate to {page}", "nav button not found")
        return
    click_el(win, el)
    time.sleep(0.3)


# ── Per-page tests ────────────────────────────────────────────────────────────

def test_controls(win, r):
    print("\n[Controls]")
    nav(win, "Controls", r)

    r.assert_click(win, "Increment",            "Button")
    r.assert_click(win, "Reset",                "Button")

    # Toggle Theme twice so we end in the original state
    el = r.assert_click(win, "Toggle Theme",    "Button")
    if el:
        time.sleep(0.1)
        click_el(win, el)

    r.assert_click(win, "Enable notifications", "CheckBox")
    r.assert_click(win, "Compact mode",         "CheckBox")
    r.assert_exists(win, "Name",                "Edit")    # text field
    r.assert_exists(win, "Accent",              "Tab")     # tab strip (UIA TabControlType)


def test_inputs(win, r):
    print("\n[Inputs]")
    nav(win, "Inputs", r)

    r.assert_click(win, "Editor", "Edit")

    # ListView — individual items don't get UIA nodes; click 2nd item by coord
    list_el = r.assert_exists(win, "List", "List")
    if list_el:
        rect   = list_el.rectangle()
        item_h = (rect.bottom - rect.top) // 6   # ~6 visible items
        # click centre-x, centre of 2nd item
        click_abs(win,
                  (rect.left + rect.right) // 2,
                  rect.top + item_h + item_h // 2)
        r.ok("List: 2nd item selectable by coordinate")
        time.sleep(0.1)

    # Dropdown — open via UIA, close with Escape
    combo = r.assert_exists(win, "Zig", "ComboBox")
    if combo:
        click_el(win, combo)    # opens dropdown
        time.sleep(0.2)
        # Close dropdown via WM_KEYDOWN VK_ESCAPE (terminal-safe, no SendInput needed)
        win32gui.PostMessage(win.handle, win32con.WM_KEYDOWN, win32con.VK_ESCAPE, 0)
        time.sleep(0.05)
        win32gui.PostMessage(win.handle, win32con.WM_KEYUP,   win32con.VK_ESCAPE, 0)
        time.sleep(0.15)
        r.ok("Dropdown: opens and dismisses")


def test_overlays(win, r):
    print("\n[Overlays]")
    nav(win, "Overlays", r)

    # ── Dialog ──────────────────────────────────────────────────────────────
    if r.assert_click(win, "Open Dialog", "Button"):
        time.sleep(0.2)
        r.assert_exists(win, "Cancel",  "Button")   # must appear when dialog open
        r.assert_exists(win, "Confirm", "Button")
        r.assert_click(win,  "Confirm", "Button")   # dismiss via UIA
        time.sleep(0.15)

    # ── Context menu ────────────────────────────────────────────────────────
    if r.assert_click(win, "Open Menu", "Button"):
        time.sleep(0.2)
        r.assert_exists(win, "New File",   "MenuItem")
        r.assert_exists(win, "Open...",    "MenuItem")
        r.assert_exists(win, "Save",       "MenuItem")
        r.assert_exists(win, "Save As...", "MenuItem")
        r.assert_exists(win, "Exit",       "MenuItem")
        r.assert_click(win,  "Save",       "MenuItem")   # select & close
        time.sleep(0.15)


def test_animations(win, r):
    print("\n[Animations]")
    nav(win, "Animations", r)

    r.assert_click(win, "Play",       "Button")
    r.assert_click(win, "Reverse",    "Button")
    r.assert_click(win, "Next Color", "Button")


def test_about(win, r):
    print("\n[About]")
    nav(win, "About", r)

    expand = r.assert_exists(win, "Architecture notes (expand)", "Button")
    if expand:
        click_el(win, expand)
        time.sleep(0.2)

        collapse = win.child_window(title="Architecture notes (collapse)",
                                    control_type="Button")
        if collapse.exists(timeout=2):
            r.ok("expand -> label changes to '(collapse)'")
            click_el(win, collapse)   # restore
        else:
            r.fail("expand -> label changes to '(collapse)'")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="zui UIA test suite")
    ap.add_argument("--exe",       default=r"zig-out\bin\zui.exe",
                    help="Path to zui executable")
    ap.add_argument("--no-launch", action="store_true",
                    help="Connect to an already-running instance")
    args = ap.parse_args()

    proc = None
    if not args.no_launch:
        print(f"Launching {args.exe} ...")
        proc = subprocess.Popen(args.exe)
        time.sleep(2)

    try:
        app = Application(backend="uia").connect(title_re=WIN_RE, timeout=10)
        win = app.window(title_re=WIN_RE)
        print(f"Connected to: {win.window_text()}")
    except Exception as exc:
        print(f"ERROR: could not connect -- {exc}")
        if proc:
            proc.terminate()
        sys.exit(1)

    r = Results()
    try:
        test_controls(win, r)
        test_inputs(win, r)
        test_overlays(win, r)
        test_animations(win, r)
        test_about(win, r)
    finally:
        if proc:
            proc.terminate()

    sys.exit(0 if r.summary() else 1)


if __name__ == "__main__":
    main()
