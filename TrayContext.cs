namespace Wmv;

/// <summary>
/// Tray-only application context: no main window, just a notify icon with a context menu.
/// </summary>
internal sealed class TrayContext : ApplicationContext
{
    private readonly NotifyIcon _icon;
    private readonly WindowMover _mover;
    private readonly ToolStripMenuItem _enabledItem;

    public TrayContext()
    {
        _mover = new WindowMover();

        _enabledItem = new ToolStripMenuItem("有効(&E)") { Checked = true, CheckOnClick = true };
        _enabledItem.CheckedChanged += (_, _) => _mover.Enabled = _enabledItem.Checked;

        var exitItem = new ToolStripMenuItem("終了(&X)");
        exitItem.Click += (_, _) => ExitThread();

        var menu = new ContextMenuStrip();
        menu.Items.Add(_enabledItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(exitItem);

        _icon = new NotifyIcon
        {
            Icon = LoadAppIcon(),
            Text = "wmv - ミドルボタンドラッグでウインドウ移動",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _icon.DoubleClick += (_, _) => _enabledItem.Checked = !_enabledItem.Checked;
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
        }

        base.Dispose(disposing);
    }
}
