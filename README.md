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
mkdir -p TestResults
xcodebuild \
  -workspace DiscoverJesusPlatform.xcworkspace \
  -scheme DiscoverJesus \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults/ios-coverage.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  clean build test
xcrun xccov view --report --json TestResults/ios-coverage.xcresult
```

Notes:
- The active simulator can vary by machine and Xcode version.
- `CODE_SIGNING_ALLOWED=NO` keeps CI and local simulator runs free of signing credentials.
- The coverage report includes app and test targets; use the `DiscoverJesus`
  app target's line coverage as the app baseline.

## Continuous integration

GitHub Actions workflow: `.github/workflows/ios-ci.yml`

The pipeline runs on:
- pull requests targeting `dev` or `main`
- pushes to `dev` or `main`

Pipeline checks:
- Build the app and run tests on an automatically selected iOS simulator.
- Collect app line coverage, include it in the workflow summary, and upload the
  `.xcresult` report as an artifact. Coverage thresholds are not enforced until
  the platform owner approves a target.
- Fail on any build or test failure.
- Scan dependencies for known vulnerabilities:
  - pull requests and pushes: OSV scanner recursive manifest scan