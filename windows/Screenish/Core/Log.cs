//
//  Log.cs
//  Screenish
//
//  Lightweight logging + persistent crash capture. The app is a tray agent with
//  no console, so a crash would otherwise leave the user with nothing. We keep a
//  persistent per-session log on disk under %LOCALAPPDATA%\Screenish\Logs, drop
//  breadcrumbs as the app works, and on the next launch detect that the previous
//  session wrote a crash banner and promote its log to a crash report. The user
//  can then hand the folder over ("Reveal Crash Logs" in the tray menu).
//

using System.Diagnostics;
using System.IO;
using System.Text;

namespace Screenish;

internal static class Log
{
    public static void InstallCrashHandlers() => CrashReporter.Install();

    /// Record a timestamped breadcrumb to the session log so a later crash report
    /// shows what the app was doing right before it died.
    public static void Breadcrumb(string message) => CrashReporter.Breadcrumb(message);

    public static void Error(string message) => CrashReporter.Breadcrumb("error: " + message);
}

internal static class CrashReporter
{
    /// Where session logs and promoted crash reports live.
    public static readonly string LogDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Screenish", "Logs");

    private static readonly string SessionPath = Path.Combine(LogDirectory, "current-session.log");
    private const string CleanMarker = "=== CLEAN SHUTDOWN ===\n";

    /// Common prefix of every banner our handlers write. A previous session is a
    /// crash iff its log contains this — so a graceful kill (logout, Task Manager),
    /// which writes no banner, is not misreported.
    private const string CrashSentinel = "*** SCREENISH";

    /// True if the previous session wrote a crash banner. Read once at launch.
    public static bool LastSessionCrashed { get; private set; }

    private static FileStream? _session;
    private static readonly object Gate = new();

    public static void Install()
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);

            // Inspect the *previous* session before we truncate it for this run.
            PromotePreviousSessionIfCrashed();
            Prune();

            _session = new FileStream(SessionPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            WriteHeader();
        }
        catch
        {
            // Logging must never take the app down.
        }

        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            WriteCrash("UNCAUGHT EXCEPTION", e.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            Breadcrumb("unobserved task exception: " + e.Exception);
            e.SetObserved();
        };
    }

    /// Hook the WPF dispatcher too: an exception on the UI thread is logged as a
    /// crash, then allowed to terminate the process like any unhandled exception.
    public static void Attach(System.Windows.Application app)
    {
        app.DispatcherUnhandledException += (_, e) => WriteCrash("UNCAUGHT EXCEPTION (UI)", e.Exception);
    }

    private static void WriteCrash(string kind, Exception? ex)
    {
        RawWrite($"\n{CrashSentinel} {kind}: {ex?.GetType().FullName}: {ex?.Message}\n{ex}\n");
        lock (Gate) { try { _session?.Flush(true); } catch { } }
    }

    // MARK: - Session file

    private static void WriteHeader()
    {
        RawWrite(
            "===== Screenish session =====\n" +
            $"version: {AppInfo.DisplayVersion}\n" +
            $"Windows: {Environment.OSVersion.VersionString}\n" +
            $"date:    {Timestamp()}\n" +
            $"pid:     {Environment.ProcessId}\n" +
            "=============================\n\n");
    }

    public static void Breadcrumb(string message)
    {
        Debug.WriteLine(message);
        RawWrite($"[{Timestamp()}] {message}\n");
    }

    /// Append a clean-shutdown marker so a normal quit isn't mistaken for a crash.
    /// The stream stays open: a crash during teardown appends its banner *after*
    /// this marker, and detection keys on the banner, so it's still reported.
    public static void MarkCleanShutdown()
    {
        RawWrite(CleanMarker);
        lock (Gate) { try { _session?.Flush(true); } catch { } }
    }

    private static string Timestamp() => DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'");

    private static void RawWrite(string text)
    {
        lock (Gate)
        {
            if (_session == null) return;
            try
            {
                var bytes = Encoding.UTF8.GetBytes(text);
                _session.Write(bytes, 0, bytes.Length);
                _session.Flush();
            }
            catch { }
        }
    }

    // MARK: - Crash detection / promotion

    private static void PromotePreviousSessionIfCrashed()
    {
        if (!File.Exists(SessionPath)) return;
        var previous = File.ReadAllText(SessionPath);
        if (previous.Length == 0 || !previous.Contains(CrashSentinel)) return;

        LastSessionCrashed = true;
        var stamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        File.WriteAllText(Path.Combine(LogDirectory, $"crash-{stamp}.log"), previous);
    }

    /// Keep only the most recent crash reports so the folder doesn't grow without
    /// bound (current-session.log is excluded — it's the live file).
    private static void Prune(int keep = 10)
    {
        var files = new DirectoryInfo(LogDirectory).GetFiles("crash-*")
            .OrderByDescending(f => f.LastWriteTimeUtc).Skip(keep);
        foreach (var file in files)
        {
            try { file.Delete(); } catch { }
        }
    }

    /// Reveal the crash-log folder in Explorer (wired to the tray menu).
    public static void RevealInExplorer()
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{LogDirectory}\"") { UseShellExecute = true });
        }
        catch { }
    }
}
