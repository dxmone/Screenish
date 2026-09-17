//
//  BackgroundStyle.cs
//  Screenish
//
//  Non-destructive beautify state: padding, background fill, corner radius,
//  shadow, and aspect ratio. All sizes are fractions of the inner image so the
//  look is resolution-independent. The JSON shape matches the macOS client.
//

using System.Globalization;
using System.Text.Json.Nodes;
using System.Windows.Media;

namespace Screenish;

/// A named gradient background for the beautify panel.
internal sealed record GradientPreset(string Id, Color[] Colors, double Angle)
{
    public bool Equals(GradientPreset? other) => other?.Id == Id;
    public override int GetHashCode() => Id.GetHashCode();
}

internal static class GradientPresets
{
    public static readonly GradientPreset[] All =
    [
        new("Sunset", [Rgb(0xFF7E5F), Rgb(0xFEB47B)], 45),
        new("Ocean", [Rgb(0x2193B0), Rgb(0x6DD5ED)], 45),
        new("Berry", [Rgb(0x8E2DE2), Rgb(0x4A00E0)], 45),
        new("Forest", [Rgb(0x11998E), Rgb(0x38EF7D)], 45),
        new("Candy", [Rgb(0xFF6FD8), Rgb(0x3813C2)], 45),
        new("Slate", [Rgb(0x434343), Rgb(0x000000)], 45),
    ];

    /// Persisted by id only; colors/angle rehydrate from the table.
    public static GradientPreset ById(string? id) => All.FirstOrDefault(p => p.Id == id) ?? All[0];

    private static Color Rgb(int hex) =>
        Color.FromRgb((byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));
}

internal enum FillKind { None, Solid, Gradient }

internal sealed record BackgroundFill(FillKind Kind, Color Color = default, GradientPreset? Gradient = null)
{
    public static readonly BackgroundFill None = new(FillKind.None);
    public static BackgroundFill Solid(Color color) => new(FillKind.Solid, color);
    public static BackgroundFill Of(GradientPreset preset) => new(FillKind.Gradient, default, preset);

    public JsonNode ToJson() => Kind switch
    {
        FillKind.Solid => new JsonObject { ["kind"] = "solid", ["colorHex"] = Color.ToHexRgba() },
        FillKind.Gradient => new JsonObject { ["kind"] = "gradient", ["gradient"] = Gradient!.Id },
        _ => new JsonObject { ["kind"] = "none" },
    };

    public static BackgroundFill FromJson(JsonNode? node) => (string?)node?["kind"] switch
    {
        "solid" => Solid(ColorHex.Parse((string?)node!["colorHex"]) ?? Colors.White),
        "gradient" => Of(GradientPresets.ById((string?)node!["gradient"])),
        _ => None,
    };
}

internal enum AspectRatioOption
{
    Auto, Square, FourThree, SixteenNine, ThreeTwo,
    // Social presets (named ratios).
    InstagramPortrait, Story, Wide, Pinterest, YouTube,
}

internal static class AspectRatioOptions
{
    /// Generic ratios shown in the segmented control.
    public static readonly AspectRatioOption[] Basic =
        [AspectRatioOption.Auto, AspectRatioOption.Square, AspectRatioOption.FourThree,
         AspectRatioOption.SixteenNine, AspectRatioOption.ThreeTwo];

    /// Named social presets shown in the "Social size" menu.
    public static readonly AspectRatioOption[] Social =
        [AspectRatioOption.InstagramPortrait, AspectRatioOption.Story, AspectRatioOption.Wide,
         AspectRatioOption.Pinterest, AspectRatioOption.YouTube];

    public static string Label(this AspectRatioOption option) => option switch
    {
        AspectRatioOption.Auto => Loc.T("Auto"),
        AspectRatioOption.Square => "1:1",
        AspectRatioOption.FourThree => "4:3",
        AspectRatioOption.SixteenNine => "16:9",
        AspectRatioOption.ThreeTwo => "3:2",
        AspectRatioOption.InstagramPortrait => "Instagram 4:5",
        AspectRatioOption.Story => "Story 9:16",
        AspectRatioOption.Wide => "Facebook/LinkedIn 1.91:1",
        AspectRatioOption.Pinterest => "Pinterest 2:3",
        _ => "YouTube 16:9",
    };

    /// Target width/height ratio, or null for Auto (no forced ratio).
    public static double? Value(this AspectRatioOption option) => option switch
    {
        AspectRatioOption.Auto => null,
        AspectRatioOption.Square => 1,
        AspectRatioOption.FourThree => 4.0 / 3.0,
        AspectRatioOption.SixteenNine => 16.0 / 9.0,
        AspectRatioOption.ThreeTwo => 3.0 / 2.0,
        AspectRatioOption.InstagramPortrait => 4.0 / 5.0,
        AspectRatioOption.Story => 9.0 / 16.0,
        AspectRatioOption.Wide => 1.91,
        AspectRatioOption.Pinterest => 2.0 / 3.0,
        _ => 16.0 / 9.0,
    };

    // Same raw values as the macOS enum so presets are portable.
    private static readonly Dictionary<AspectRatioOption, string> Raw = new()
    {
        [AspectRatioOption.Auto] = "auto", [AspectRatioOption.Square] = "square",
        [AspectRatioOption.FourThree] = "fourThree", [AspectRatioOption.SixteenNine] = "sixteenNine",
        [AspectRatioOption.ThreeTwo] = "threeTwo", [AspectRatioOption.InstagramPortrait] = "instagramPortrait",
        [AspectRatioOption.Story] = "story", [AspectRatioOption.Wide] = "wide",
        [AspectRatioOption.Pinterest] = "pinterest", [AspectRatioOption.YouTube] = "youtube",
    };

    public static string RawValue(this AspectRatioOption option) => Raw[option];

    public static AspectRatioOption FromRaw(string? raw) =>
        Raw.FirstOrDefault(p => p.Value == raw, new(AspectRatioOption.Auto, "auto")).Key;
}

internal sealed record BackgroundStyle
{
    public double PaddingFraction { get; init; }               // 0…0.4 of the inner image's longest side
    public double InsetFraction { get; init; }                 // 0…0.1 colored frame between image and padding
    public Color InsetColor { get; init; } = Colors.White;
    public double CornerRadiusFraction { get; init; }          // 0…0.25 of the card's shortest side
    public double ShadowRadiusFraction { get; init; } = 0.04;
    public double ShadowOpacity { get; init; }
    public BackgroundFill Fill { get; init; } = BackgroundFill.None;
    public AspectRatioOption Ratio { get; init; } = AspectRatioOption.Auto;

    public static readonly BackgroundStyle None = new();

    /// True when the style would not change the image at all (renderer no-op).
    public bool IsEmpty =>
        Fill.Kind == FillKind.None && PaddingFraction == 0 && InsetFraction == 0
        && CornerRadiusFraction == 0 && ShadowOpacity == 0 && Ratio == AspectRatioOption.Auto;

    public JsonObject ToJson() => new()
    {
        ["paddingFraction"] = PaddingFraction,
        ["insetFraction"] = InsetFraction,
        ["insetColorHex"] = InsetColor.ToHexRgba(),
        ["cornerRadiusFraction"] = CornerRadiusFraction,
        ["shadowRadiusFraction"] = ShadowRadiusFraction,
        ["shadowOpacity"] = ShadowOpacity,
        ["fill"] = Fill.ToJson(),
        ["ratio"] = Ratio.RawValue(),
    };

    /// Rejects non-finite / out-of-range fractions on decode: a corrupt value would
    /// otherwise request an enormous bitmap on the next capture. Falls back to the
    /// property default, then clamps to the documented range.
    public static BackgroundStyle FromJson(JsonNode? node)
    {
        var defaults = new BackgroundStyle();
        if (node is not JsonObject) return defaults;

        double Clamped(string key, double fallback, double min, double max)
        {
            double value;
            try { value = (double?)node[key] ?? fallback; } catch { value = fallback; }
            if (!double.IsFinite(value)) value = fallback;
            return Math.Min(Math.Max(value, min), max);
        }

        return new BackgroundStyle
        {
            PaddingFraction = Clamped("paddingFraction", defaults.PaddingFraction, 0, 0.4),
            InsetFraction = Clamped("insetFraction", defaults.InsetFraction, 0, 0.1),
            InsetColor = ColorHex.Parse((string?)node["insetColorHex"]) ?? Colors.White,
            CornerRadiusFraction = Clamped("cornerRadiusFraction", defaults.CornerRadiusFraction, 0, 0.25),
            ShadowRadiusFraction = Clamped("shadowRadiusFraction", defaults.ShadowRadiusFraction, 0, 0.5),
            ShadowOpacity = Clamped("shadowOpacity", defaults.ShadowOpacity, 0, 1),
            Fill = BackgroundFill.FromJson(node["fill"]),
            Ratio = AspectRatioOptions.FromRaw((string?)node["ratio"]),
        };
    }
}

/// A named, persisted beautify preset.
internal sealed record BeautyPreset(Guid Id, string Name, BackgroundStyle Style)
{
    public JsonObject ToJson() => new()
    {
        ["id"] = Id.ToString().ToUpperInvariant(),
        ["name"] = Name,
        ["style"] = Style.ToJson(),
    };

    public static BeautyPreset? FromJson(JsonNode? node)
    {
        if (node is not JsonObject || !Guid.TryParse((string?)node["id"], out var id)) return null;
        return new BeautyPreset(id, (string?)node["name"] ?? "", BackgroundStyle.FromJson(node["style"]));
    }
}

internal static class ColorHex
{
    /// "#RRGGBBAA" in sRGB.
    public static string ToHexRgba(this Color c) => $"#{c.R:X2}{c.G:X2}{c.B:X2}{c.A:X2}";

    public static Color? Parse(string? hex)
    {
        if (hex == null) return null;
        var s = hex.TrimStart('#');
        if (s.Length != 8 || !uint.TryParse(s, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v))
            return null;
        return Color.FromArgb((byte)(v & 0xFF), (byte)((v >> 24) & 0xFF),
                              (byte)((v >> 16) & 0xFF), (byte)((v >> 8) & 0xFF));
    }
}
