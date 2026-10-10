# iPhone/iPad release checklist

## Product decisions

- App Store / Home Screen name: **Unofficial Gaelic Companion**.
- Full in-app title: **Unofficial Companion to "Scottish Gaelic in Twelve Weeks"**.
- Free; no ads, purchases, accounts, analytics, or app-operated cloud sync.
- Bundle ID: `io.myers.GaelicCompanion`. Keep it stable after release.
- Support: `https://app.myers.io/gaelic_companion`.
- Privacy: `https://app.myers.io/gaelic_companion/privacy`.
- The Mac editor remains a developer tool. Its sandboxing is not a release gate
  for this iOS product.

## Before publication

- [ ] Retain publisher permission and ownership clearance privately. Check that
  permission covers the actual public name, descriptions, and bundled metadata.
  Do not put private correspondence in Git.
- [ ] Inspect all Git history and prospective artifacts for credentials,
  recordings, scans, personal data, and third-party material before changing
  repository visibility. A clean current tree is not a history audit.
- [ ] Publish the support page using `docs/SUPPORT.md` and the privacy policy using
  `Companion/Resources/PrivacyPolicy.txt`. Verify both intended URLs on a device.
  The bundled privacy policy works offline, but hosting is still required.
- [ ] Provide a working private contact route on the support page and its
  appropriate website/contact privacy notice. App privacy text does not describe
  the site's logs, cookies, or handling of support correspondence.
- [ ] Enable GitHub private vulnerability reporting and Issues; then explicitly
  make the repository public when ready.
- [ ] Inspect the icon on actual Home Screens and create original store
  screenshots on supported iPhone/iPad sizes. Do not use publisher artwork.

## Apple setup

- [ ] Select the owner's Apple Developer signing team locally and register the
  bundle identifier; never commit certificates, private keys, or profiles.
- [ ] Create the App Store Connect record, description, keywords, category,
  copyright, support/privacy URLs, and current age-rating answers.
- [ ] Set free pricing and intended territories. Complete applicable regional
  declarations, including EU trader status if distributing there.
- [ ] Review export compliance for the actual binary and dependencies; answer
  Apple's questionnaire rather than assuming encryption exemption.
- [ ] Complete App Privacy. This implementation has no developer data collection
  or tracking; verify the final dependency list before choosing "Data Not Collected".
  Apple/OS backups and external websites are described separately in the policy.
- [ ] Check the final archive's privacy report: the app declares UserDefaults
  for its own preferences (`CA92.1`) and file metadata within its container
  (`C617.1`) or explicitly selected files (`3B52.1`). ZIPFoundation supplies its
  own manifest; retain that resource and its bundled MIT acknowledgement.
- [ ] Increase the build number for each upload, archive with production
  signing, validate in Organizer, and upload to TestFlight.

Apple's published minimum as checked October 10, 2026 is Xcode 26 with the
iOS/iPadOS 26 SDK for uploads. The iOS 17 deployment target is separate.
Recheck https://developer.apple.com/news/upcoming-requirements/ before upload.

## Review resources

Run `python3 scripts/create_review_sample.py` to create `build/ReviewSample.zip`.
It contains the project's original quiet tone with valid title tags, covering
Lesson 1, one appendix, and one reading-practice recording. It has no book audio.
The script refuses to overwrite an existing output; use a new output path when
regenerating. The ZIP is not bundled in either production app.

Publish that ZIP at a stable reviewer-accessible URL, then put the actual URL
in App Review notes. Draft notes:

> This is a free, independent player for user-imported audio. No login, payment,
> or publisher audio is included. For review, download our original synthetic
> sample ZIP from [INSERT VERIFIED SAMPLE URL], save it in Files, then choose
> "Import downloaded ZIP". The displayed lesson names come from the normal
> catalog; sample recordings are quiet tones, not language lessons.
> Play a recording and try seeking, background/lock-screen controls, and manual
> listened status. About & download contains privacy/support information and
> import replacement. Each sample is about four seconds, so an intro marker
> outside its duration correctly falls back to playback from the beginning.

Do not submit with the placeholder or rely solely on the publisher's website.
Use a fresh installation for the sample: importing replaces the current library.

## Validation gates

- [ ] CI passes on the proposed release commit. CI covers unit tests, clean
  onboarding/privacy UI, iOS Release compilation, and Mac editor compilation.
  Imported-library UI tests require separately prepared fixtures and are not
  implied by a green clean-install CI run.
- [ ] Review a signed Release archive: icon, display name, privacy and license
  resources, no debug mapping UI, and no sample/publisher audio.
- [ ] Test fresh installation, sample import, original user-authorized ZIP
  import, replacement, cancellation, corrupt/oversized ZIPs, and low storage.
- [ ] Exercise background/lock-screen playback, interruptions, headphones,
  seeking, intro skipping, and progress persistence on physical devices.
- [ ] Check VoiceOver, large Dynamic Type, light/dark mode, rotation, and iPad.
- [ ] Confirm policy links work before/after import and offline documents work.
- [ ] Run external TestFlight, resolve reported blockers, then submit for review.

Regenerate the original app icon with `xcrun swift scripts/generate_app_icon.swift`.
It uses only original drawing code and Apple system graphics APIs.
