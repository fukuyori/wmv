namespace Wmv;

/// <summary>
/// Invisible top-level window whose only job is to receive close requests.
/// wmv has no main window, so without this Restart Manager (used by the installer),
/// "taskkill" without /F and session shutdown would have nothing to send WM_CLOSE to.
/// </summary>
internal sealed class ShutdownWindow : NativeWindow
{
    private const int WM_CLOSE = 0x0010;
    private const int WM_QUERYENDSESSION = 0x0011;
    private const int WM_ENDSESSION = 0x0016;

    private const int WS_EX_TOOLWINDOW = 0x00000080; // Keep it out of Alt+Tab and the taskbar.

    private readonly Action _onCloseRequested;

    public ShutdownWindow(Action onCloseRequested)
    {
        _onCloseRequested = onCloseRequested;
        CreateHandle(new CreateParams
        {
            Caption = "wmv",
            ExStyle = WS_EX_TOOLWINDOW,
            // No WS_VISIBLE: the window is never shown.
        });
    }

    protected override void WndProc(ref Message m)
    {
        switch (m.Msg)
        {
            case WM_CLOSE:
                _onCloseRequested();
                return;

            case WM_QUERYENDSESSION:
                m.Result = 1; // We can be shut down at any time.
                return;

            case WM_ENDSESSION:
                if (m.WParam != IntPtr.Zero)
                {
                    _onCloseRequested();
                }
                return;
        }

        base.WndProc(ref m);
    }
}
