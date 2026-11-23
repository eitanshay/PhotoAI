# polish for iOS (ES-07)

Native SwiftUI version of the polish web app. Same pipeline: a Gemini text model reads the photo and writes the shot brief, a Gemini image model rebuilds it, and for photos with people a face check compares before and after and retries if the face drifted.

What the native version adds:

- Picks straight from your photo library (HEIC works natively, no converter).
- **Save to Photos** puts the result in your library, in a "polish" album, with the original photo's capture date and location. It sits next to the original in your timeline.
- The Gemini API key lives in the iOS Keychain.
- The library is kept on the phone (SwiftData), and any item can be reopened, compared, saved again or regenerated.

## Layout

| Path | What |
| --- | --- |
| `Polish.xcodeproj` | Generated project, one app target, shared scheme `Polish` |
| `Polish/App` | App entry, settings store, the enhance session (state and flow) |
| `Polish/UI` | Screens and components in the Eitan Shay design system |
| `Polish/Platform` | ImageIO (decode, crops, EXIF and GPS), Photos saving, Keychain, SwiftData model |
| `Polish/Resources` | Figtree and JetBrains Mono (OFL), app icon, colors |
| `PolishCore` | Prompts, Gemini client, parsing, face check and retry logic. Compiled into the app and unit-tested with `swift test` |
| `scripts/generate_project.rb` | Regenerates the Xcode project (`gem install xcodeproj && ruby scripts/generate_project.rb`) |

The project only needs regenerating when files are added or removed. Codemagic builds the committed project as is.

## First build (Codemagic to TestFlight)

This is the same setup as BloomTrack. You only do it once.

1. **Register the bundle ID.** In the Apple Developer portal, go to Identifiers and add an App ID `com.eitanshay.polish`. No extra capabilities are needed. To use a different ID, change it in `codemagic.yaml` and run `BUNDLE_ID=your.id ruby scripts/generate_project.rb`.
2. **Create the profile.** Still in the Developer portal, go to Profiles and add an App Store distribution profile for that ID. Use the same distribution certificate Codemagic already holds for BloomTrack.
3. **Fetch it into Codemagic.** In Codemagic, go to Team settings, codemagic.yaml settings, Code signing identities, iOS provisioning profiles, Fetch profiles, and pick the new polish profile.
4. **Create the app record.** In App Store Connect, go to Apps, then + New App. Choose iOS and the bundle ID from step 1. The name must be unique on the App Store, so "polish" alone will be taken; use something like "polish ES-07". The home screen still shows "polish". Then open General, App Information and copy the numeric **Apple ID**.
5. **Fill in `codemagic.yaml`** at the repo root:
   - `app_store_connect:` is the API key name from Codemagic Team integrations. It is the same value as in BloomTrack's codemagic.yaml.
   - `APP_STORE_APPLE_ID:` is the number from step 4.
6. **Commit and push.** Codemagic builds on pushes to `main` that touch `ios/` or `codemagic.yaml`. If the PhotoAI repo is not yet an app in Codemagic, add it first. You can also start the "polish iOS to TestFlight" workflow by hand.
7. **Install.** When Apple finishes processing (usually 10 to 30 minutes after the upload), the build shows in TestFlight for internal testers. If you are not in an internal group for this app yet, add yourself under App Store Connect, TestFlight, Internal Testing.
8. **First launch.** Open polish, then Settings, and paste your Gemini key.

Each later push to `ios/` gives a new TestFlight build automatically, numbered from the last one.
