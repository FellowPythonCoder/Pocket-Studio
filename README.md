# Pocket Studio

A native SwiftUI macOS app for importing DJI Osmo Pocket 3 media, previewing clips, downloading selected files, and publishing selected footage to a GitHub repository.

## Requirements
- macOS 13 or newer
- Xcode 15+ (or Swift 5.9+)
- DJI Pocket 3 connected over USB-C and set to **File Transfer**
- GitHub OAuth App Client ID (one-time app setup)
- `git-lfs` for large media: `brew install git-lfs`

## Run
1. Unzip the project.
2. Open Terminal in this folder.
3. Run:

   ```bash
   swift run
   ```

Or open `Package.swift` in Xcode and run the `PocketStudio` scheme.

## Pocket 3 connection
Power on the camera, connect USB-C, and tap **File Transfer** on the camera. macOS must mount the camera/card under `/Volumes` for this app to browse it. If it does not mount, use a microSD card reader. DJI recommends a card reader for some Mac connection issues.

## GitHub
Create a GitHub OAuth App at https://github.com/settings/developers. Enable **Device Flow** in its settings, then copy its Client ID into `GitHubOAuthConfig.swift` (the constant is currently in `AppModel.swift`). Device Flow uses browser-based GitHub approval: click **Sign in with GitHub**, approve the app in the browser, and return to Pocket Studio. No token needs to be pasted. The resulting access token is stored in macOS Keychain. The OAuth app requests the `repo` scope so it can create a repository and push selected files.

## Important large-file limitations
- This starter supports GitHub repository creation and basic Git push.
- Large video files need Git LFS. Install with `brew install git-lfs`.
- GitHub Free and Pro LFS individual file limit is 2 GB.
- GitHub also limits a single push to 2 GB. The current starter refuses a selected batch above 1.8 GB instead of attempting a push that will fail.
- A 15 GB collection needs multiple batches, LFS quota/billing, and enough internet upload bandwidth. No app can make the transfer faster than the connection and GitHub's limits.

## OAuth setup note\nThe app needs the Client ID of an OAuth App you register. This is a public app identifier, not a password or client secret. The app cannot ship with a shared client ID unless its publisher owns and operates the OAuth app.\n\n## Current limitations
- Device discovery is based on mounted macOS volumes. It does not implement a proprietary MTP driver; the Pocket 3 must appear as a mounted volume.
- GitHub upload is a starter implementation; large media batching, robust retries/resume, LFS quota preflight, and OAuth device authorization are not yet implemented.
- The app copies files; it never deletes or formats camera media.
