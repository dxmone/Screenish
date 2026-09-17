//
//  Preferences.cs
//  Screenish
//
//  Centralized access to user preferences, persisted as JSON in
//  %APPDATA%\Screenish\settings.json. Same keys as the macOS client's
//  UserDefaults, so beautify presets are portable between the two.
//

using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace Screenish;

internal static class Prefs
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Screenish", "settings.json");

    private static JsonObject _root = new();

    /// False until the first save — i.e. on the very first launch for this user.
    public static bool Exists => File.Exists(FilePath);

    public static void Load()
    {
        try
        {
            if (File.Exists(FilePath) && JsonNode.Parse(File.ReadAllText(FilePath)) is JsonObject root)
                _root = root;
        }
        catch (Exception ex)
        {
            Log.Error("settings unreadable, using defaults: " + ex.Message);
        }
    }

    private static void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, _root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (Exception ex)
        {
            Log.Error("settings save failed: " + ex.Message);
        }
    }

    private static bool GetBool(string key, bool fallback)
    {
        try { return (bool?)_root[key] ?? fallback; } catch { return fallback; }
    }

    private static string? GetString(string key)
    {
        try { return (string?)_root[key]; } catch { return null; }
    }

    private static void Set(string key, JsonNode? value)
    {
        _root[key] = value;
        Save();
    }

    // MARK: - General

    public static string DefaultSaveDirectory
    {
        get
        {
            var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            return pictures.Length > 0 ? pictures : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }
    }

    /// Empty = the default (Pictures).
    public static string SaveLocationPath
    {
        get => GetString("saveLocationPath") ?? "";
        set => Set("saveLocationPath", value);
    }

    public static string SaveLocation => SaveLocationPath.Length > 0 ? SaveLocationPath : DefaultSaveDirectory;

    public static bool HideAtLaunch
    {
        get => GetBool("hideAtLaunch", true);
        set => Set("hideAtLaunch", value);
    }

    public static bool CompressJpeg
    {
        get => GetBool("compressJPEG", false);
        set => Set("compressJPEG", value);
    }

    public static bool RemoveAfterDrag
    {
        get => GetBool("removeAfterDrag", false);
        set => Set("removeAfterDrag", value);
    }

    /// Drop a shot from the Stack once it has been saved to the folder from the editor.
    public static bool RemoveAfterSave
    {
        get => GetBool("removeAfterSave", false);
        set => Set("removeAfterSave", value);
    }

    public static bool OpenEditorAfterCapture
    {
        get => GetBool("openEditorAfterCapture", true);
        set => Set("openEditorAfterCapture", value);
    }

    /// The export format implied by the compress-to-JPG preference.
    public static ImageFormat Format => CompressJpeg ? ImageFormat.Jpeg : ImageFormat.Png;

    public static AppLanguage Language
    {
        get => GetString("language") switch
        {
            "en" => AppLanguage.English,
            "sv" => AppLanguage.Swedish,
            _ => AppLanguage.System,
        };
        set => Set("language", value switch
        {
            AppLanguage.English => "en",
            AppLanguage.Swedish => "sv",
            _ => null,
        });
    }

    // MARK: - Beautify

    /// Last-used beautify style, updated on each edit (Done). First run is a gentle
    /// gradient with a little padding.
    public static BackgroundStyle LastUsedBackground
    {
        get => _root["defaultBackgroundStyle"] is JsonObject node
            ? BackgroundStyle.FromJson(node)
            : new BackgroundStyle
            {
                Fill = BackgroundFill.Of(GradientPresets.All[0]),
                PaddingFraction = 0.06,
                CornerRadiusFraction = 0.03,
            };
        set => Set("defaultBackgroundStyle", value.ToJson());
    }

    /// A pinned default preset, if the user set one. Overrides last-used for new captures.
    public static Guid? DefaultPresetId
    {
        get => Guid.TryParse(GetString("defaultPresetID"), out var id) ? id : null;
        set => Set("defaultPresetID", value?.ToString().ToUpperInvariant());
    }

    /// Beautify applied to a new capture: the pinned default preset if set (and it
    /// still exists), otherwise the last-used style.
    public static BackgroundStyle DefaultBackground
    {
        get
        {
            if (DefaultPresetId is Guid id && SavedPresets.FirstOrDefault(p => p.Id == id) is { } preset)
                return preset.Style;
            return LastUsedBackground;
        }
    }

    /// Named beautify presets the user has saved.
    public static List<BeautyPreset> SavedPresets
    {
        get => _root["beautyPresets"] is JsonArray array
            ? array.Select(BeautyPreset.FromJson).OfType<BeautyPreset>().ToList()
            : [];
        set => Set("beautyPresets", new JsonArray(value.Select(p => (JsonNode)p.ToJson()).ToArray()));
    }

    // MARK: - Shortcuts

    public static Hotkey? GetHotkey(CaptureMode mode)
    {
        var node = _root["shortcuts"]?[mode.ToString()];
        if (node == null) return Hotkey.Default(mode);      // never customised
        return Hotkey.FromJson(node);                       // null = cleared by the user
    }

    public static void SetHotkey(CaptureMode mode, Hotkey? hotkey)
    {
        if (_root["shortcuts"] is not JsonObject shortcuts)
            _root["shortcuts"] = shortcuts = new JsonObject();
        shortcuts[mode.ToString()] = hotkey?.ToJson() ?? new JsonObject();
        Save();
    }
}

/// "Launch at login": a per-user Run key entry pointing at the installed exe.
internal static class LoginItem
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Screenish";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) != null;
        }
    }

    public static void Set(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled) key.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        catch (Exception ex)
        {
            Log.Error("login item update failed: " + ex.Message);
        }
    }
}

internal static class AppRelauncher
{
    public static void Relaunch()
    {
        try
        {
            // --relaunch makes the new instance wait for this one to release the
            // single-instance mutex instead of exiting immediately.
            System.Diagnostics.Process.Start(Environment.ProcessPath!, "--relaunch");
        }
        catch (Exception ex)
        {
            Log.Error("relaunch failed: " + ex.Message);
            return;
        }
        System.Windows.Application.Current.Shutdown();
    }
}
