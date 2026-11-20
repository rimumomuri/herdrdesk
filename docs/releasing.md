# Release checklist

1. Build from a fresh checkout on a Mac with Swift 6 and Node.js 22. Test Core discovery with no private labels, old preferences, shell terminals and labelled coding agents.
2. Verify switching between English, Korean and Japanese, restarting the app, switching observation targets, and stopping observation on close. Test a local and a remote Mac connected through Core.
3. Use isolated terminals to check a successful send, stale session rejection, ambiguous delivery with no automatic retry, and read-only terminal output. Open a selected terminal in Herdr and verify destination identity.
4. Check the source and proposed release assets for private team data, conversation history, screen captures from real accounts, signing credentials and local backups. Include only synthetic examples. Confirm the project license and all third-party notices.
5. For GitHub Releases binaries, use a Developer ID Application identity with `HERDRDESK_SIGN_IDENTITY` and follow [Apple's notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/). Check the signed app after extracting it on a clean Mac. Local ad-hoc builds are for local testing.
