# Screenish

Screenshot software (macOS/Swift, Xcode project).

## Workflow rules

- Commit after every change. One change = one commit.
- Work on `main` branch only. No feature branches unless explicitly told otherwise.

## Versioning & release

- `MARKETING_VERSION` in `project.pbxproj` (set in BOTH Debug and Release configs) is
  the app version, semver `X.Y.Z`. Bump it before every release build and commit the
  bump: patch for bug fixes, minor for new features, major for big milestones.
- `CURRENT_PROJECT_VERSION` (build number) is derived automatically at build time as
  the git commit count (`git rev-list --count HEAD`). Never edit it by hand; the
  placeholder `1` in project.pbxproj only applies to plain Xcode/debug builds.
- Release build + export: `./scripts/export-release.sh` — builds Release with the
  injected build number and drops `Screenish-<version>-b<build>.zip` in `~/Downloads`.
