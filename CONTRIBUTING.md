# Contributing

Use the build instructions in [README.md](README.md). The iOS app is the public
product; the Mac intro editor is a developer tool, not a Mac App Store release.

Before sending a pull request:

- Explain the behavior being changed and add focused tests.
- Keep UI accessible with VoiceOver labels/identifiers and Dynamic Type support.
- Preserve user audio, metadata, and listening progress across changes.
- Update `project.yml` and regenerate the checked-in project with XcodeGen when
  adding/removing app or test files. Review generated changes before committing.
- Run the relevant unit/UI tests. Tests must use original synthetic audio and
  isolated storage, never an imported personal library.
- Do not add analytics, networking, or new SDKs without discussing privacy and
  updating the manifest, policy, and third-party notices.

Never attach publisher recordings, book scans, credentials, signing material,
or private personal data to a commit, issue, screenshot, or test artifact.
Submit code and original assets only when you have the right to contribute them
under this repository's MIT license. That license does not grant rights to the
book, trademarks, or user-imported recordings.

Report ordinary bugs through GitHub Issues once the repository is public.
For suspected vulnerabilities, follow [SECURITY.md](SECURITY.md).
