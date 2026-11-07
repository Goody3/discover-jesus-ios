# discover-jesus-ios

Code used to create iOS app for discovering Jesus.

## Canonical Xcode entrypoint

Use the workspace and scheme below for local development and CI:

- Workspace: `DiscoverJesusPlatform.xcworkspace`
- Scheme: `DiscoverJesus`
- Project resolved by the workspace: `DiscoverJesus/DiscoverJesus.xcodeproj`

## Local build and test

From the repository root:

```bash
xcodebuild -workspace DiscoverJesusPlatform.xcworkspace -scheme DiscoverJesus -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO clean build test
```

Notes:
- The active simulator can vary by machine and Xcode version.
- `CODE_SIGNING_ALLOWED=NO` keeps CI and local simulator runs free of signing credentials.

## Continuous integration

GitHub Actions workflow: `.github/workflows/ios-ci.yml`

The pipeline runs on:
- pull requests targeting `dev` or `main`
- pushes to `dev` or `main`

Pipeline checks:
- Build the app and run tests on an automatically selected iOS simulator.
- Fail on any build or test failure.
- Scan dependencies for known vulnerabilities:
  - pull requests and pushes: OSV scanner recursive manifest scan