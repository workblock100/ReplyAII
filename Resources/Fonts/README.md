# Fonts

Drop the following `.ttf` / `.otf` files into this directory. The app auto-registers every font in this folder at launch via `ATSApplicationFontsPath` in `Info.plist`.

## Required files

| File                              | Source                                                              | PostScript name used in Theme.Font |
| --------------------------------- | ------------------------------------------------------------------- | ---------------------------------- |
| `InterTight-Regular.ttf`          | https://fonts.google.com/specimen/Inter+Tight                       | `Inter Tight`                      |
| `InterTight-Medium.ttf`           | —                                                                   | `Inter Tight` @ weight `.medium`   |
| `InterTight-SemiBold.ttf`         | —                                                                   | `Inter Tight` @ weight `.semibold` |
| `InterTight-Bold.ttf`             | —                                                                   | `Inter Tight` @ weight `.bold`     |
| `InstrumentSerif-Italic.ttf`      | https://fonts.google.com/specimen/Instrument+Serif                  | `Instrument Serif Italic`          |
| `JetBrainsMono-Regular.ttf`       | https://fonts.google.com/specimen/JetBrains+Mono                    | `JetBrainsMono-Regular`            |
| `JetBrainsMono-Medium.ttf`        | —                                                                   | `JetBrainsMono-Medium`             |

Everything above is OFL-licensed (free to bundle and redistribute).

## Verify after install

1. `xcodegen generate`
2. Build and launch the app.
3. Open Font Book → Validate → drag one of the `.ttf` files in to confirm the PostScript name matches what `Theme.Font.sans/serifItalic/mono` expects.

If `Theme.Font` silently falls back to system font, the name in `Theme.swift` does not match the actual PostScript name of the installed file — fix the `.custom(...)` call, not the file name.
