# Fonts

The app auto-registers every font in this directory at launch via
`ATSApplicationFontsPath` in `Info.plist`. Files are bundled and committed.

## Shipped files

| File                         | Source                                                            | How Theme.Font references it                   |
| ---------------------------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| `InterTight[wght].ttf`       | google/fonts `ofl/intertight/InterTight[wght].ttf` (variable)     | `.custom("Inter Tight", size:).weight(...)`    |
| `InstrumentSerif-Italic.ttf` | google/fonts `ofl/instrumentserif/InstrumentSerif-Italic.ttf`     | `.custom("InstrumentSerif-Italic", size:)`     |
| `JetBrainsMono-Regular.ttf`  | JetBrains/JetBrainsMono `fonts/ttf/JetBrainsMono-Regular.ttf`     | `.custom("JetBrainsMono-Regular", size:)`      |
| `JetBrainsMono-Medium.ttf`   | JetBrains/JetBrainsMono `fonts/ttf/JetBrainsMono-Medium.ttf`      | `.custom("JetBrainsMono-Medium", size:)`       |

All OFL-licensed. Inter Tight is a variable font — `.weight(...)` picks the
correct instance via the `wght` axis. JetBrains Mono ships as per-weight
statics because we only need Regular and Medium.

## Verified PostScript names

Confirmed by running a CoreText dump against each TTF at ingest time:

- Inter Tight family exposes `InterTight-Regular` plus named instances for
  Thin / ExtraLight / Light / Medium / SemiBold / Bold / ExtraBold / Black.
- Instrument Serif → `InstrumentSerif-Italic`.
- JetBrains Mono → `JetBrainsMono-Regular`, `JetBrainsMono-Medium`.
