using System.Runtime.InteropServices;
using static Wmv.NativeMethods;

namespace Wmv;

/// <summary>
/// Low-level mouse hook (WH_MOUSE_LL). Must be created on a thread that pumps messages.
/// </summary>
internal sealed class MouseHook : IDisposable
{
    /// <summary>
    /// Handler for hook events. Return true to swallow the event (it will not reach other applications).
    /// </summary>
    public delegate bool MouseEventHandler(int message, in MSLLHOOKSTRUCT info);

    // Keep the delegate alive; otherwise the GC may collect it while the hook is installed.
    private readonly LowLevelMouseProc _proc;
    private IntPtr _hook;

    public MouseEventHandler? Handler { get; set; }

    public MouseHook()
    {
        _proc = HookCallback;
        _hook = SetWindowsHookExW(WH_MOUSE_LL, _proc, GetModuleHandleW(null), 0);
        if (_hook == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "SetWindowsHookEx failed.");
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && Handler is { } handler)
        {
            var info = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            bool swallow;
            try
            {
                swallow = handler((int)wParam, in info);
            }
            catch
            {
                // Never let an exception escape a hook callback.
                swallow = false;
            }

            if (swallow)
            {
                return 1;
            }
        }

        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
