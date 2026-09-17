//
//  AppInfo.cs
//  Screenish
//
//  App version (semver from the csproj) + build number (git commit count,
//  injected at build time), and shell helpers shared across the app.
//

using System.Diagnostics;
using System.Reflection;

namespace Screenish;

internal static class AppInfo
{
    public const string RepoUrl = "https://github.com/dxmone/Screenish";

    /// "1.2.0 (123)" — version plus build number, like the macOS About tab.
    public static string DisplayVersion
    {
        get
        {
            var info = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "1.0";
            var parts = info.Split('+', 2);
            return parts.Length == 2 && parts[1] != parts[0] ? $"{parts[0]} ({parts[1]})" : parts[0];
        }
    }

    /// Open Explorer with the file selected (Finder's "reveal").
    public static void RevealInExplorer(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        }
        catch { }
    }

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }
}
