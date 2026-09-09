using Microsoft.Win32;

namespace Wmv;

/// <summary>
/// Registers or unregisters wmv in the per-user Run key so it starts at sign-in.
/// The installer's "start at sign-in" task writes the same value, so both stay in sync.
/// </summary>
internal static class StartupManager
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "wmv";

    private static string CommandLine => "\"" + Application.ExecutablePath + "\"";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
                return key?.GetValue(ValueName) is string value
                    && string.Equals(value, CommandLine, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using RegistryKey? key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (key is null)
        {
            throw new InvalidOperationException("Could not open the Run registry key.");
        }

        if (enabled)
        {
            key.SetValue(ValueName, CommandLine, RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
