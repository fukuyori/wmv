namespace Wmv;

/// <summary>
/// Tray-only application context: no main window, just a notify icon with a context menu.
/// </summary>
internal sealed class TrayContext : ApplicationContext
{
    private readonly NotifyIcon _icon;
    private readonly WindowMover _mover;
    private readonly ShutdownWindow _shutdownWindow;
    private readonly ToolStripMenuItem _enabledItem;
    private readonly ToolStripMenuItem _startupItem;

    public TrayContext()
    {
        _mover = new WindowMover();
        _shutdownWindow = new ShutdownWindow(ExitThread);

        _enabledItem = new ToolStripMenuItem("&Enabled") { Checked = true, CheckOnClick = true };
        _enabledItem.CheckedChanged += (_, _) => _mover.Enabled = _enabledItem.Checked;

        _startupItem = new ToolStripMenuItem("&Start at sign-in");
        _startupItem.Click += (_, _) => ToggleStartup();

        var exitItem = new ToolStripMenuItem("E&xit");
        exitItem.Click += (_, _) => ExitThread();

        var menu = new ContextMenuStrip();
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_startupItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(exitItem);
        // Re-read the registry each time so changes made by the installer or by hand are reflected.
        menu.Opening += (_, _) => _startupItem.Checked = StartupManager.IsEnabled;

        _icon = new NotifyIcon
        {
            Icon = LoadAppIcon(),
            Text = "wmv - move windows with middle-button drag",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.DoubleClick += (_, _) => _enabledItem.Checked = !_enabledItem.Checked;
    }

    private void ToggleStartup()
    {
        bool enable = !StartupManager.IsEnabled;
        try
        {
            StartupManager.SetEnabled(enable);
            _startupItem.Checked = enable;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not change the start-at-sign-in setting.\n" + ex.Message,
                "wmv", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static Icon LoadAppIcon()
    {
        using Stream? stream = typeof(TrayContext).Assembly.GetManifestResourceStream("wmv.ico");
        if (stream is null)
        {
            return SystemIcons.Application;
        }

        // Pick the size the shell uses for tray icons on the current DPI.
        return new Icon(stream, SystemInformation.SmallIconSize);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _icon.Visible = false;
            _icon.Dispose();
            _mover.Dispose();
            _shutdownWindow.DestroyHandle();
        }

        base.Dispose(disposing);
    }
}
