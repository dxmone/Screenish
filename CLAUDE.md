# Screenish

Screenshot software with one client per platform:

- `macos/` — the macOS client (Swift, Xcode project).
- `windows/` — the Windows client (C#/.NET 8, WPF) + its WiX MSI installer.

The Windows client mirrors the macOS one 1:1 — same features, same folder/file layout
(`Capture/`, `Core/`, `Editor/`, `Stack/`, `Settings/`, `Background/`), same constants
and UI strings. A feature or fix is not done until it exists in BOTH clients; new UI
strings need a Swedish translation in both `macos/Screenish/Localizable.xcstrings` and
`windows/Screenish/Settings/Loc.cs`. See `docs/adr/0004-windows-client-wpf-mirror.md`.

## Workflow rules

- Commit after every change. One change = one commit.
- Work on `main` branch only. No feature branches unless explicitly told otherwise.

## Versioning & release

- Both clients share ONE app version, semver `X.Y.Z`. Bump it in both places before every
  release build and commit the bump: patch for bug fixes, minor for new features, major
  for big milestones.
  - macOS: `MARKETING_VERSION` in `macos/Screenish.xcodeproj/project.pbxproj` (set in BOTH
    Debug and Release configs).
  - Windows: `<Version>` in `windows/Screenish/Screenish.csproj`.
- The build number is derived automatically at build time as the git commit count
  (`git rev-list --count HEAD`). Never edit it by hand; the placeholder `1`
  (`CURRENT_PROJECT_VERSION` in project.pbxproj, `BuildNumber` in the csproj) only applies
  to plain Xcode/debug builds.
- macOS release build + export: `./macos/scripts/export-release.sh` — builds Release with
  the injected build number and drops `Screenish-<version>-b<build>.zip` in `~/Downloads`.
- Windows release build + export: `.\windows\scripts\export-release.ps1` — publishes
  self-contained win-x64 with the injected build number, packages the MSI with WiX and
  drops `Screenish-<version>-b<build>.msi` in `~\Downloads`. Never change the
  `UpgradeCode` in `windows/Installer/Package.wxs` (upgrades depend on it).

## Verifying the Windows client

- `dotnet build windows\Screenish\Screenish.csproj` must be warning-free.
- `Screenish.exe --render-test <dir>` writes PNGs of every annotation kind, a beautified
  composite and the editor UI — look at them after touching rendering or layout.
- `Screenish.exe --smoke-test` runs capture → stack → editor → overlay without user
  input; the exit code is the number of failed checks.
