using System.Runtime.InteropServices;
using static Wmv.NativeMethods;

namespace Wmv;

/// <summary>
/// Moves the top-level window under the cursor while the middle mouse button is held down.
/// A middle click without movement is re-sent to the target so that ordinary middle-click
/// behaviour (e.g. "open link in new tab") keeps working.
/// </summary>
internal sealed class WindowMover : IDisposable
{
    private const uint WM_APPLY_MOVE = WM_APP + 1;
    private const uint WM_REPLAY_CLICK = WM_APP + 2;

    /// <summary>Virtual key that turns a middle-button drag into a resize (VK_SHIFT, VK_CONTROL, or VK_MENU).</summary>
    private const int ResizeModifierKey = VK_SHIFT;

    private const int MinWindowWidth = 150;
    private const int MinWindowHeight = 50;

    [Flags]
    private enum Edges
    {
        None = 0,
        Left = 1,
        Top = 2,
        Right = 4,
        Bottom = 8,
    }

    // Marker put into dwExtraInfo of events we inject, so the hook can recognise them.
    private static readonly UIntPtr InjectedMarker = new(0x574D5631); // "WMV1"

    // System windows that must never be dragged (same set as PowerToys Grab and Move, plus WorkerW and menus).
    private static readonly string[] ExcludedClasses =
    [
        "Progman",                                          // Desktop
        "WorkerW",                                          // Desktop (behind icons)
        "Shell_TrayWnd",                                    // Taskbar
        "Shell_SecondaryTrayWnd",                           // Taskbar on secondary monitors
        "NotifyIconOverflowWindow",                         // Tray overflow
        "TopLevelWindowForOverflowXamlIsland",              // Tray overflow (Win11)
        "tooltips_class32",                                 // Tooltips
        "MultitaskingViewFrame",                            // Task view
        "XamlExplorerHostIslandWindow",                     // Explorer XAML islands
        "Windows.UI.Composition.DesktopWindowContentBridge",
        "Shell_InputSwitchTopLevelWindow",                  // Input method switcher
        "#32768",                                           // Popup menu
    ];

    private readonly MouseHook _hook;
    private readonly MessageWindow _window;
    private readonly uint _ownProcessId;

    // Drag state. Written from the hook callback (UI thread), read from WndProc (same thread).
    private IntPtr _target;
    private POINT _startPoint;
    private POINT _lastPoint;
    private RECT _startRect;
    private bool _pressed;
    private bool _moved;
    private bool _restorePending;
    private bool _movePosted;
    private Edges _resizeEdges; // None = move, otherwise resize the given edges.

    public bool Enabled { get; set; } = true;

    /// <summary>Distance in pixels the cursor must travel before a press becomes a drag.</summary>
    public Size DragThreshold { get; set; }

    public WindowMover()
    {
        _ownProcessId = (uint)Environment.ProcessId;
        DragThreshold = SystemInformation.DragSize;
        _window = new MessageWindow(this);
        _hook = new MouseHook { Handler = OnMouseEvent };
    }

    private bool OnMouseEvent(int message, in MSLLHOOKSTRUCT info)
    {
        // Pass through events injected by ourselves (replayed middle clicks).
        if ((info.flags & LLMHF_INJECTED) != 0 || info.dwExtraInfo == InjectedMarker)
        {
            return false;
        }

        switch (message)
        {
            case WM_MBUTTONDOWN:
                return OnMiddleDown(info.pt);
            case WM_MOUSEMOVE:
                return OnMove(info.pt);
            case WM_MBUTTONUP:
                return OnMiddleUp();
            default:
                return false;
        }
    }

    private bool OnMiddleDown(POINT pt)
    {
        if (!Enabled)
        {
            return false;
        }

        IntPtr target = FindMovableWindow(pt);
        if (target == IntPtr.Zero)
        {
            return false;
        }

        if (!GetWindowRect(target, out RECT rect))
        {
            return false;
        }

        bool maximized = IsZoomed(target);
        Edges edges = Edges.None;
        if (!maximized && IsModifierDown(ResizeModifierKey) && IsResizable(target))
        {
            edges = ClosestHandle(pt, rect);
        }

        _target = target;
        _startPoint = pt;
        _lastPoint = pt;
        _startRect = rect;
        _pressed = true;
        _moved = false;
        _restorePending = maximized;
        _movePosted = false;
        _resizeEdges = edges;
        return true; // Swallow: the target must not see the button press.
    }

    private bool OnMove(POINT pt)
    {
        if (!_pressed)
        {
            return false;
        }

        if (!_moved)
        {
            int dx = pt.X - _startPoint.X;
            int dy = pt.Y - _startPoint.Y;
            if (Math.Abs(dx) < DragThreshold.Width && Math.Abs(dy) < DragThreshold.Height)
            {
                return false;
            }

            _moved = true;
        }

        _lastPoint = pt;

        // Coalesce: the hook must return quickly, so apply the move from the message loop.
        if (!_movePosted)
        {
            _movePosted = true;
            PostMessageW(_window.Handle, WM_APPLY_MOVE, IntPtr.Zero, IntPtr.Zero);
        }

        // Never swallow WM_MOUSEMOVE; doing so would freeze the cursor.
        return false;
    }

    private bool OnMiddleUp()
    {
        if (!_pressed)
        {
            return false;
        }

        _pressed = false;
        bool moved = _moved;
        _moved = false;

        if (!moved)
        {
            // Plain middle click: replay it so the target application receives it.
            PostMessageW(_window.Handle, WM_REPLAY_CLICK, IntPtr.Zero, IntPtr.Zero);
        }

        return true; // Swallow the matching button release.
    }

    private IntPtr FindMovableWindow(POINT pt)
    {
        IntPtr hwnd = WindowFromPoint(pt);
        if (hwnd == IntPtr.Zero)
        {
            return IntPtr.Zero;
        }

        IntPtr root = GetAncestor(hwnd, GA_ROOT);
        if (root == IntPtr.Zero)
        {
            root = hwnd;
        }

        GetWindowThreadProcessId(root, out uint pid);
        if (pid == _ownProcessId)
        {
            return IntPtr.Zero;
        }

        if (IsIconic(root))
        {
            return IntPtr.Zero;
        }

        string className = GetClassName(root);
        if (Array.IndexOf(ExcludedClasses, className) >= 0)
        {
            return IntPtr.Zero;
        }

        return root;
    }

    private static bool IsModifierDown(int vKey) => (GetAsyncKeyState(vKey) & 0x8000) != 0;

    private static bool IsResizable(IntPtr hwnd)
    {
        long style = GetWindowLongPtrW(hwnd, GWL_STYLE).ToInt64();
        return (style & WS_THICKFRAME) != 0;
    }

    /// <summary>Picks the corner or edge midpoint closest to the grab point (8 handles).</summary>
    private static Edges ClosestHandle(POINT pt, RECT rect)
    {
        int midX = rect.Left + rect.Width / 2;
        int midY = rect.Top + rect.Height / 2;

        (Edges edges, int x, int y)[] handles =
        [
            (Edges.Left | Edges.Top, rect.Left, rect.Top),
            (Edges.Top, midX, rect.Top),
            (Edges.Right | Edges.Top, rect.Right, rect.Top),
            (Edges.Right, rect.Right, midY),
            (Edges.Right | Edges.Bottom, rect.Right, rect.Bottom),
            (Edges.Bottom, midX, rect.Bottom),
            (Edges.Left | Edges.Bottom, rect.Left, rect.Bottom),
            (Edges.Left, rect.Left, midY),
        ];

        Edges best = Edges.Right | Edges.Bottom;
        long bestDistance = long.MaxValue;
        foreach (var (edges, x, y) in handles)
        {
            long dx = pt.X - x;
            long dy = pt.Y - y;
            long distance = dx * dx + dy * dy;
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = edges;
            }
        }

        return best;
    }

    private static string GetClassName(IntPtr hwnd)
    {
        var buffer = new char[256];
        int length = GetClassNameW(hwnd, buffer, buffer.Length);
        return length > 0 ? new string(buffer, 0, length) : string.Empty;
    }

    private void ApplyPendingMove()
    {
        _movePosted = false;

        if (!_pressed || _target == IntPtr.Zero || !IsWindow(_target))
        {
            _pressed = false;
            return;
        }

        if (_restorePending)
        {
            _restorePending = false;
            if (!RestoreMaximizedUnderCursor())
            {
                _pressed = false;
                return;
            }
        }

        int dx = _lastPoint.X - _startPoint.X;
        int dy = _lastPoint.Y - _startPoint.Y;
        bool ok;

        if (_resizeEdges == Edges.None)
        {
            ok = SetWindowPos(_target, IntPtr.Zero, _startRect.Left + dx, _startRect.Top + dy, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
        }
        else
        {
            RECT r = ResizedRect(_startRect, _resizeEdges, dx, dy);
            ok = SetWindowPos(_target, IntPtr.Zero, r.Left, r.Top, r.Width, r.Height,
                SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
        }

        // If SetWindowPos fails (e.g. elevated window under UIPI), give up on this drag.
        if (!ok)
        {
            _pressed = false;
        }
    }

    /// <summary>Applies the cursor delta to the selected edges, keeping the opposite edges fixed and enforcing a minimum size.</summary>
    private static RECT ResizedRect(RECT start, Edges edges, int dx, int dy)
    {
        RECT r = start;

        if ((edges & Edges.Left) != 0)
        {
            r.Left = Math.Min(start.Left + dx, start.Right - MinWindowWidth);
        }
        else if ((edges & Edges.Right) != 0)
        {
            r.Right = Math.Max(start.Right + dx, start.Left + MinWindowWidth);
        }

        if ((edges & Edges.Top) != 0)
        {
            r.Top = Math.Min(start.Top + dy, start.Bottom - MinWindowHeight);
        }
        else if ((edges & Edges.Bottom) != 0)
        {
            r.Bottom = Math.Max(start.Bottom + dy, start.Top + MinWindowHeight);
        }

        return r;
    }

    /// <summary>
    /// Restores a maximized target and repositions it so that the grab point keeps the same
    /// relative position inside the window (like dragging a maximized window by its title bar).
    /// </summary>
    private bool RestoreMaximizedUnderCursor()
    {
        RECT maxRect = _startRect;
        if (maxRect.Width <= 0 || maxRect.Height <= 0)
        {
            return false;
        }

        ShowWindow(_target, SW_RESTORE);
        if (!GetWindowRect(_target, out RECT restored))
        {
            return false;
        }

        long relX = (long)(_startPoint.X - maxRect.Left) * restored.Width / maxRect.Width;
        long relY = (long)(_startPoint.Y - maxRect.Top) * restored.Height / maxRect.Height;

        _startRect = new RECT
        {
            Left = _startPoint.X - (int)relX,
            Top = _startPoint.Y - (int)relY,
            Right = _startPoint.X - (int)relX + restored.Width,
            Bottom = _startPoint.Y - (int)relY + restored.Height,
        };
        return true;
    }

    private static void ReplayMiddleClick()
    {
        var inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE;
        inputs[0].mi.dwFlags = MOUSEEVENTF_MIDDLEDOWN;
        inputs[0].mi.dwExtraInfo = InjectedMarker;
        inputs[1].type = INPUT_MOUSE;
        inputs[1].mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
        inputs[1].mi.dwExtraInfo = InjectedMarker;
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    public void Dispose()
    {
        _hook.Dispose();
        _window.DestroyHandle();
    }

    /// <summary>Hidden message-only window used to run work on the message loop outside the hook callback.</summary>
    private sealed class MessageWindow : NativeWindow
    {
        private const int HWND_MESSAGE = -3;

        private readonly WindowMover _owner;

        public MessageWindow(WindowMover owner)
        {
            _owner = owner;
            CreateHandle(new CreateParams { Parent = new IntPtr(HWND_MESSAGE) });
        }

        protected override void WndProc(ref Message m)
        {
            switch ((uint)m.Msg)
            {
                case WM_APPLY_MOVE:
                    _owner.ApplyPendingMove();
                    return;
                case WM_REPLAY_CLICK:
                    ReplayMiddleClick();
                    return;
            }

            base.WndProc(ref m);
        }
    }
}
