# ios_app

`ios_app/` is the native iOS host for Omnibot.

## What lives here

- `Runner/Host/`: SwiftUI host shell and Flutter engine bootstrap.
- `Runner/Bridges/`: typed host bridge registration plus legacy channel compatibility.
- `Runner/Runtime/`: iOS terminal/workspace runtime coordinator.
- `Runner/Models/`: local model orchestration backed by OmniInfer iOS when available.
- `Runner/Browser/`: browser session snapshot state shared with Flutter.

## Build notes

- This host embeds the Flutter module from `/Users/ocean/code/OmnibotApp/ui`.
- Run `flutter pub get` in `ui/` before opening `ios_app/Runner.xcworkspace`.
- CocoaPods resolves Flutter dependencies through `ios_app/Podfile`.
- Full `xcodebuild` validation requires a machine with full Xcode installed.
