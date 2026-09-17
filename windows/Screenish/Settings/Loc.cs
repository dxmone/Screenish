//
//  Loc.cs
//  Screenish
//
//  String localization. English is the key (same keys as the macOS client's
//  Localizable.xcstrings); Swedish is looked up in the table below. The
//  language is resolved once at launch — changing it requires a relaunch.
//

using System.Globalization;

namespace Screenish;

internal enum AppLanguage { System, English, Swedish }

internal static class Loc
{
    private static bool _swedish;

    public static void Init()
    {
        _swedish = Prefs.Language switch
        {
            AppLanguage.Swedish => true,
            AppLanguage.English => false,
            _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "sv",
        };
    }

    /// Translate an English key to the active language.
    public static string T(string key) =>
        _swedish && Swedish.TryGetValue(key, out var value) ? value : key;

    public static string Label(this AppLanguage language) => language switch
    {
        AppLanguage.English => "English",
        AppLanguage.Swedish => "Svenska",
        _ => T("System"),
    };

    private static readonly Dictionary<string, string> Swedish = new()
    {
        ["About"] = "Om",
        ["Add a numbered step marker"] = "Lägg till en numrerad stegmarkör",
        ["Add text"] = "Lägg till text",
        ["Always hide window at launch"] = "Dölj alltid fönster vid start",
        ["Apply edits and update the shot in the stack"] = "Tillämpa ändringar och uppdatera bilden i stacken",
        ["Arrow"] = "Pil",
        ["Arrow style"] = "Pilstil",
        ["Aspect Ratio"] = "Bildförhållande",
        ["Auto"] = "Auto",
        ["Background"] = "Bakgrund",
        ["Blur"] = "Oskärpa",
        ["Blur an area to hide sensitive info"] = "Gör ett område oskarpt för att dölja känslig info",
        ["Boxed"] = "Ruta",
        ["Cancel"] = "Avbryt",
        ["Capture Area"] = "Fånga område",
        ["Capture Full Screen"] = "Fånga hel skärm",
        ["Capture Window"] = "Fånga fönster",
        ["Choose…"] = "Välj…",
        ["Clear all edits"] = "Rensa alla ändringar",
        ["Click to reveal the crash log so you can share it."] = "Klicka för att visa kraschloggen så att du kan dela den.",
        ["Color"] = "Färg",
        ["Compress to JPG when saving"] = "Komprimera till JPG vid sparning",
        ["Copy"] = "Kopiera",
        ["Copy and Remove"] = "Kopiera och ta bort",
        ["Copy the image to the clipboard"] = "Kopiera bilden till urklipp",
        ["Corner Radius"] = "Hörnradie",
        ["Couldn’t save the screenshot"] = "Det gick inte att spara skärmbilden",
        ["Counter"] = "Räknare",
        ["Created by Thomas Strömberg with AI coding."] = "Skapad av Thomas Strömberg med AI-kodning.",
        ["Crop"] = "Beskär",
        ["Crop the image"] = "Beskär bilden",
        ["Delete"] = "Ta bort",
        ["Delete selected"] = "Ta bort markerat",
        ["Done"] = "Klar",
        ["Drag"] = "Dra",
        ["Drag the image into another app"] = "Dra bilden till en annan app",
        ["Draw a filled rectangle"] = "Rita en fylld rektangel",
        ["Draw a line"] = "Rita en linje",
        ["Draw a rectangle outline"] = "Rita en rektangelkontur",
        ["Draw an arrow"] = "Rita en pil",
        ["Draw an ellipse or circle"] = "Rita en ellips eller cirkel",
        ["Draw freehand"] = "Rita på fri hand",
        ["Edit Screenshot"] = "Redigera skärmbild",
        ["Ellipse"] = "Ellips",
        ["Fill"] = "Fyllning",
        ["Filled Rectangle"] = "Fylld rektangel",
        ["General"] = "Allmänt",
        ["Highlight"] = "Markering",
        ["Highlight an area (marker)"] = "Markera ett område (överstrykning)",
        ["Inset"] = "Inramning",
        ["Language"] = "Språk",
        ["Later"] = "Senare",
        ["Launch at login"] = "Starta vid inloggning",
        ["Line"] = "Linje",
        ["Monospaced"] = "Monospace",
        ["Monospaced Boxed"] = "Monospace-ruta",
        ["No background"] = "Ingen bakgrund",
        ["No saved presets"] = "Inga sparade förinställningar",
        ["None"] = "Ingen",
        ["Open editor after capture"] = "Öppna redigeraren efter tagen bild",
        ["Outlined"] = "Konturerad",
        ["Padding"] = "Marginal",
        ["Pencil"] = "Penna",
        ["Pixelate"] = "Pixelera",
        ["Pixelate an area to hide sensitive info"] = "Pixelera ett område för att dölja känslig info",
        ["Preset"] = "Förinställning",
        ["Preset name"] = "Namn på förinställning",
        ["Press shortcut…"] = "Tryck kortkommando…",
        ["Quit Screenish"] = "Avsluta Screenish",
        ["Record shortcut"] = "Spela in kortkommando",
        ["Rectangle"] = "Rektangel",
        ["Redo"] = "Gör om",
        ["Relaunch now"] = "Starta om nu",
        ["Remove"] = "Ta bort",
        ["Remove from stack after drag and drop"] = "Ta bort från stacken efter drag-och-släpp",
        ["Remove from stack after saving in editor"] = "Ta bort från stacken efter att ha sparat i redigeraren",
        ["Restart required"] = "Omstart krävs",
        ["Restart Screenish to apply the new language."] = "Starta om Screenish för att tillämpa det nya språket.",
        ["Reveal Crash Logs"] = "Visa kraschloggar",
        ["Rounded"] = "Rundad",
        ["Rounded Boxed"] = "Rundad ruta",
        ["Save"] = "Spara",
        ["Save current…"] = "Spara nuvarande…",
        ["Save preset"] = "Spara förinställning",
        ["Save the image to your folder"] = "Spara bilden till din mapp",
        ["Save to"] = "Spara till",
        ["Save to Folder"] = "Spara till mapp",
        ["Screenish crashed last session"] = "Screenish kraschade förra sessionen",
        ["Select"] = "Markera",
        ["Select and move objects"] = "Markera och flytta objekt",
        ["Set as default"] = "Sätt som standard",
        ["Settings…"] = "Inställningar…",
        ["Screenish Settings"] = "Inställningar för Screenish",
        ["Shadow"] = "Skugga",
        ["Shortcuts"] = "Kortkommandon",
        ["Social size"] = "Social storlek",
        ["Spotlight"] = "Strålkastare",
        ["Spotlight an area (darken the rest)"] = "Lyft fram ett område (mörka resten)",
        ["Standard"] = "Standard",
        ["System"] = "System",
        ["Text"] = "Text",
        ["Text size"] = "Textstorlek",
        ["Text style"] = "Textstil",
        ["The image couldn’t be encoded."] = "Bilden kunde inte kodas.",
        ["The shortcut {0} is already in use by another app."] = "Kortkommandot {0} används redan av en annan app.",
        ["Thickness"] = "Tjocklek",
        ["Undo"] = "Ångra",
        ["Version {0}"] = "Version {0}",
    };
}
