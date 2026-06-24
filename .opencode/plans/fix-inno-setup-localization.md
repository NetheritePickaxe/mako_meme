# Fix Inno Setup Chinese Localization for CI

## Problem
CI build failed because `ChineseSimplified.isl` file is not available on the `windows-2025-vs2026` runner. The `[Languages]` section in `tools/setup.iss` references this file and causes compilation to abort.

## Plan
1. Remove the `[Languages]` section from `tools/setup.iss`
2. Add `[CustomMessages]` section with Chinese translations of all key Inno Setup wizard strings
3. This avoids the missing `.isl` file while still localizing the installer UI

## Files to change
- `tools/setup.iss` — remove `[Languages]`, add `[CustomMessages]`

## CustomMessages to override
- SetupTitle, SetupAppTitle
- SelectDirDesc, SelectDirBrowseLabel, SelectDirPrompt
- SelectStartMenuDesc, SelectStartMenuPrompt
- SelectTaskDesc
- ReadyLabel, ReadyLabel2, ReadyToInstallLabel, ShouldInstallLabel
- InstallCaption, InstallProgressCaption
- InstalledCaption, InstallCompletedLabel
- FinishLabel, FinishNoAutomationLabel
- CancelInstallCaption, CancelInstallMessage
- SelectLanguage, LanguageDescription
- All error messages (optional, skip non-critical ones)
