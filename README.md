# Unofficial Companion to 'Scottish Gaelic In 12 Weeks'

A native SwiftUI iPhone/iPad app (iOS 17+) for listening to user-imported book audio.
The app contains **no recordings**, does not fetch audio, and is not affiliated with
the book's authors or publisher.

## Run

Open `GaelicCompanion.xcodeproj`, choose the `GaelicCompanion` scheme and an iOS
simulator, then Run. For a physical device, select your own development team under
Signing & Capabilities. The display name is the full requested title; iOS may
truncate long names on the Home Screen.

ZIPFoundation 0.9.20 is pinned through Swift Package Manager. Xcode resolves it on
first build. The checked-in Xcode project is ready to use; XcodeGen is only needed
after changing `project.yml` or adding/removing source files:

```sh
xcodegen generate
xcodebuild -project GaelicCompanion.xcodeproj -scheme GaelicCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build -parallel-testing-enabled NO test
```

Choose an installed simulator name if different. Build settings are explicit in
`project.yml`, rather than relying on an XcodeGen installation's preset files.

## Import and listen

1. Use **Open publisher's download page** in the app and manually download the ZIP.
2. Save the original ZIP in Files, return to the app, and choose **Import audio**.
3. Browse **Lesson → Section → Recording**. Subsections share their numbered
   parent section; a section can contain only subsection recordings when the
   source has no main recording.

Conversation recordings are shown directly within their provisional lesson.
Appendices and Reading Practice have separate top-level groups. Playback includes
pause/resume, seeking, 15-second skips, background audio and lock-screen controls.
Recordings do not automatically advance. Audio-session transitions are serialized
off the UI thread; stopping or pausing invalidates pending playback requests.

Successfully finishing a recording marks that recording listened. A lesson is
listened only after **all recordings mapped to it** have finished, including its
conversation. Missing, unimported recordings prevent automatic lesson completion.
Swipe a lesson/recording row, or use the lesson's **…** menu, to manually mark it
listened or unlistened. Manual lesson toggles update all its mapped recordings.
Status persists across launches and ZIP replacement; it is keyed by numeric track
ID, so changing lesson assignments recalculates lesson completion naturally.
About & download also offers a confirmed progress reset.

## Correct the editable metadata mapping

Edit **`Companion/Resources/TrackMapping.json`** and rebuild. No reimport is needed
for mapping corrections to existing recordings. This file is the authority for
the hierarchy; the app does **not** attempt to detect lesson boundaries at runtime.

The mapping contains all 150 individual recordings (IDs 002–151). ID 001 is the
aggregate and is always ignored. Actual ID3 Title metadata is read and persisted
during import; the editable mapping's title is used for display.

```json
{
  "id": 7,
  "lesson": 1,
  "section": 4,
  "subsection": "a",
  "group": "lesson",
  "title": "4a Prepositional Pronouns",
  "needsReview": false
}
```

| Field | Meaning |
| --- | --- |
| `id` | Numeric final three digits of the source filename; unique, excluding 001. |
| `lesson` | 1–12 for lesson tracks; `null` for bonus groups. |
| `section` | Global book section number, never restarted per lesson; `null` for conversations/bonus tracks. |
| `subsection` | Lowercase suffix such as `"a"`; `null` for a main section. Requires a section number. |
| `group` | `"lesson"`, `"appendices"` or `"readingPractice"`. |
| `title` | Editable display title, initially copied from the supplied ID3 Title. |
| `needsReview` | `true` displays a provisional-mapping warning. Set to `false` after checking against the book. |

**Assignments still need your manual review.** IDs 002–009 implement the confirmed
examples. IDs 010–144 are flagged for review: lesson boundaries are provisionally
placed after each of the 12 Conversation tracks, and unnumbered section titles
were counted upward. Explicit section numbers and gaps are preserved. In particular,
the early metadata has missing numbers (e.g. an unnumbered title followed by `14a`,
and a later jump to `22a`), so some inferred section numbers are not authoritative.
Appendices 145–147 and Reading Practice 148–151 identify themselves.
Original title typos are retained for easy comparison with the source.

Keep `schemaVersion` at 1. Invalid mappings fail visibly instead of dropping tracks.
If new recordings are supported, add their IDs to this file first. Importing an
unmapped numeric ID is an error, not a silent omission.

## Storage and validation

- Audio is held in the app's private Application Support directory and excluded
  from backup. The original ZIP is not retained.
- Files named `[digits]_[three digits].mp3` can be nested inside ZIP directories.
  Resource-fork entries and unrelated files are ignored.
- Duplicate track IDs, unsafe paths, symlinks, checksum mismatches, missing Title
  metadata and unplayable audio are rejected. Streaming extraction enforces
  512 MiB per recording and 3 GiB total limits.
- Partial imports are allowed and show an imported/expected count. Replacement
  replaces, rather than merges, the audio library.
- Imports are staged in separate generations and published via an atomic manifest.
  Failure/cancellation preserves the previous library. Obsolete generations are
  removed after successful replacement and release of the old player; startup
  also reclaims generations left by an interrupted process.
- Listening progress is stored separately from audio, with atomic writes.

`Audio/`, MP3s, ZIPs and build outputs are ignored by Git and excluded from app
resources. Do not add publisher recordings to the project, commits, or releases.

## Tests

Tests cover catalog validation/grouping, explicit subsection gaps, safe ZIP
extraction, corruption and rollback, saved libraries, missing files, playback
completion, persistent/manual listened status, and onboarding/file-picker access.
Test archives and playback WAVs are generated from original synthetic data.

When the local `Audio/` folder exists, an optional integration test builds a
temporary ZIP of its 150 individual tracks and exercises the production importer
and ID3 reader. It skips when local audio is absent; no publisher audio is bundled
in the app or test target. Temporary fixtures are deleted by the tests.
