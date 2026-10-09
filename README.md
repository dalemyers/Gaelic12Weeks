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
2. Save the original ZIP in Files, return to the app, and choose **Import downloaded ZIP**.
3. Browse **Lesson → Section → Recording**. Subsections share their numbered
   parent section; a section can contain only subsection recordings when the
   source has no main recording.

Conversation recordings are shown directly within their mapped lesson.
Appendices and Reading Practice have separate top-level groups. Playback includes
pause/resume, seeking, 5-second skips, background audio and lock-screen controls.
Before the first successful import, onboarding shows the download instructions
and its primary ZIP import action, without a player or import/info toolbar buttons.
Import progress and cancellation remain available during extraction.
Once audio is imported, the compact bottom player stays visible while browsing
lessons and sections, during replacement imports, and in About & download.
Before a recording is selected it shows "Select a recording" with disabled controls.
Navigation and the player/import footer occupy separate layout regions, so the
last row can scroll fully above the player even when its height changes.
Recordings do not automatically advance. Audio-session transitions are serialized
off the UI thread; stopping or pausing invalidates pending playback requests.

Successfully finishing a recording marks that recording listened. A lesson is
listened only after **all recordings mapped to it** have finished, including its
conversation. Missing, unimported recordings prevent automatic lesson completion.
A section likewise shows a listened checkmark when all recordings mapped to that
section are listened, including its main recording (if present) and every
subsection. Marking any of them unlistened removes the section's checkmark.
Section status is derived from saved recording progress, so already-completed
sections appear correctly without replaying their audio.
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

**All 150 recordings (IDs 002–151) have been confirmed through the mapping review.**
The reviewed section assignments supersede the initial inferred numbering.
Track 030 ("Days, Months And Seasons") is Section 25, and track 031
("Emphatic Suffixes") is Section 26. Appendices 145–147 and Reading Practice
148–151 are also confirmed.
Titles retain their source wording and typos unless explicitly corrected during
review; the section/subsection fields determine the hierarchy, even when a title
contains a different number.

Keep `schemaVersion` at 1. Invalid mappings fail visibly instead of dropping tracks.
If new recordings are supported, add their IDs to this file first. Importing an
unmapped numeric ID is an error, not a silent omission.

## Confirm and correct mappings in DEBUG

Run the **Debug** configuration, import your audio, and open **About & download →
Review audio mapping (DEBUG)**. This tool is compiled out of Release builds.

The reviewer shows the track ID, imported filename, original MP3 Title, bundled
assignment, and editable **group, lesson, section, subsection, title and note**.
Use **Play this recording** and the bottom player's pause/seek/5-second controls
to check the recording against the book. Review listening never marks a recording,
section or lesson listened. Entering and leaving review stops the previous audio.

- **Confirm & next** saves corrections, clears `needsReview`, and advances to the
  next track in the current filter. At the end it stays on the confirmed track.
  Increasing or decreasing a section number shifts later unconfirmed numbered
  recordings by the same amount, across lesson boundaries.
- **Save correction for review** saves edits without confirming them and sets
  `needsReview` to `true`.
- **Mark incorrect** saves the current corrections/note, records an incorrect
  decision, and keeps `needsReview` set.
- **Show** filters all, unconfirmed, incorrect or confirmed tracks. **Choose track**
  jumps to a particular recording; Previous/Next follow numeric filename IDs.
  Unimported recordings can be edited but cannot be played.

Automatic section shifts follow numeric filename IDs, not the active filter.
Already-confirmed recordings (in the draft or bundled mapping), conversations
without sections, and bonus tracks are left alone. Subsection letters, titles,
notes and lesson assignments are preserved; shifted proposals still need review.
The confirmation notice reports how many recordings shifted and by how much.

**Save correction for review** and **Mark incorrect** retain a pending section
offset without shifting anything yet. Confirmation applies that pending offset
once, even after relaunching. Confirming an automatically shifted proposal as-is
does not shift everything again. Further edits to an already confirmed track
apply only the new difference. Adding or removing a section number does not
infer an offset. Invalid results (below Section 1 or integer overflow) and write
failures reject the entire save, leaving the draft unchanged.

Blank section/subsection fields are supported for conversations and main tracks.
Bonus groups clear lesson/section/subsection fields on save. Invalid values fail
visibly without replacing your previous saved decision. Leaving an unsaved editor
requires confirmation; export is disabled until edits are saved or confirmed.

Decisions and corrections persist in a separate `MappingReview.json` in Application
Support. They are a **review draft**, not a live replacement of the normal library's
mapping. Existing `needsReview: false` source rows still start *unreviewed* in this
tool; untouched rows preserve their original flags when exported and confirmed
source rows are protected from automatic shifts. Older review backups remain
readable; previously confirmed corrections are not automatically replayed.

Choose **Export corrected TrackMapping.json** to save the complete, validated
150-track mapping through Files. Replace `Companion/Resources/TrackMapping.json`
with that exported file, inspect its diff, and rebuild. No audio reimport is needed.
Only metadata is exported, never audio. **Export saved review backup** additionally
preserves decisions, original rows and notes; it is not a replacement for the
bundled mapping. The corrected mapping intentionally contains no review-only fields.

If a bundled row changes after you saved a draft, the tool refuses to overwrite it
with a stale correction. Export a backup, then explicitly **Reset review draft**
to restart against the new source. Applying this tool's own exported correction
is recognized and does not invalidate its matching saved decision. Reset affects
only review edits, not imported audio or listened progress.

Run `GaelicCompanionUITests/MappingReviewUITests` only on a dedicated test simulator
with an imported synthetic library (the MiniPlayerLibrary fixture below suffices):
it resets that simulator's review draft, edits sample assignments, and saves a
uniquely named JSON export in Files. It verifies persistence, unsaved-change
protection, confirmation, and export without changing the bundled mapping.
The opt-in `testResetWriteFailureWhenBlockedFixtureIsPresent` additionally needs
`Library/Application Support/MappingReview.json` to be a directory in that test
app's container. Run it separately: it checks that both load and reset errors
remain visible. Remove that blocking fixture before running the normal review test.

## Storage and validation

- Audio is held in the app's private Application Support directory and excluded
  from backup. The original ZIP is not retained.
- Files named `[digits]_[three digits].mp3` can be nested inside ZIP directories.
  Resource-fork entries and unrelated files are ignored.
- Duplicate track IDs, unsafe paths, symlinks, checksum mismatches, missing Title
  metadata and unplayable audio are rejected. Streaming extraction enforces
  512 MiB per recording and 3 GiB total limits.
- Partial imports are allowed and show a missing-recordings notice, without a
  permanent imported-count banner. After importing, use **About & download →
  Replace imported audio** to choose another ZIP; the library toolbar no longer
  shows the import button. Replacement replaces, rather than merges, the audio library.
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

`testPlayerAcrossLibraryNavigation` is an opt-in UI integration check using a
one-minute synthetic recording. On a **dedicated simulator**, first run
`testOnboardingBeforeImport` with no imported library, then seed the fixture below
and run only `GaelicCompanionUITests/OnboardingTests/testPlayerAcrossLibraryNavigation`.
Do not seed a simulator containing a real user's library. This requires an
existing `ffmpeg` installation; no publisher recordings are used.
The same fixture supports `OnboardingTests/testLibraryReplacementLivesInAbout`,
which checks the removed banner/toolbar action and cancellation of replacement
from About without losing the imported library.

```sh
# Set SIMULATOR_ID to your dedicated, booted test simulator with this app installed.
CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.dalemyers.GaelicCompanion data) &&
LIBRARY="$CONTAINER/Library/Application Support/ImportedLibrary" &&
GENERATION=A1815CE7-4570-4B28-8A8D-7D347B45EE54 &&
test ! -e "$LIBRARY/Current.json" &&
mkdir -p "$LIBRARY/$GENERATION" &&
ffmpeg -nostdin -v error -n -f lavfi -i anullsrc=r=44100:cl=mono -t 60 \
  -metadata title="Synthetic mini-player fixture" "$LIBRARY/$GENERATION/1_002.mp3" &&
cp TestSupport/MiniPlayerLibrary/Current.json "$LIBRARY/Current.json"
```

The section-completion UI regression
`GaelicCompanionUITests/OnboardingTests/testSectionListenedStatusFollowsChildren`
uses a separate fresh simulator fixture: set `GENERATION` to
`84EF3E94-3346-4516-8BB4-5702C7D7F6B5`, generate the same one-minute silent MP3
as `1_006.mp3`, copy it to `1_007.mp3` and `1_008.mp3` in that generation, and
use `TestSupport/SectionLibrary/Current.json` as the manifest. Run only that UI
test against the fixture. It checks partial completion, completion after the last
subsection finishes playing, persistence across relaunch, and clearing the
section's checkmark when a child is marked unlistened. Both seeded UI checks skip
when their required library is absent; onboarding needs a fresh installation.

`OnboardingTests/testOnboardingBeforeImport` checks that the onboarding import
action is reachable in portrait and landscape, the player and toolbar controls
are absent, and cancelling the picker or relaunching preserves this state.
`PlayerLayoutUITests/testBottomRowsStayAbovePlayer` checks the final library,
lesson and section rows, landscape playback, and About. It requires a complete
synthetic library on a dedicated simulator. After creating the one-minute
MiniPlayerLibrary fixture above, extend it to all mapped IDs:

```sh
for ID in $(jq -r '.tracks[].id' Companion/Resources/TrackMapping.json); do
  if [ "$ID" -ne 2 ]; then
    cp "$LIBRARY/$GENERATION/1_002.mp3" \
      "$LIBRARY/$GENERATION/$(printf '1_%03d.mp3' "$ID")" || exit 1
  fi
done
jq --arg generation "$GENERATION" \
  '{directory: $generation, manifest: {schemaVersion: 1, tracks: [.tracks[] |
    {id, filename: ("1_" + (("000" + (.id | tostring))[-3:]) + ".mp3"),
     metadataTitle: "Synthetic layout fixture"}]}}' \
  Companion/Resources/TrackMapping.json > "$LIBRARY/Current.json"
```

These checks assert that each complete row is above the player's top edge, not
just that XCTest reports the row as hittable.

When the local `Audio/` folder exists, an optional integration test builds a
temporary ZIP of its 150 individual tracks and exercises the production importer
and ID3 reader. It skips when local audio is absent; no publisher audio is bundled
in the app or test target. Temporary fixtures are deleted by the tests.
