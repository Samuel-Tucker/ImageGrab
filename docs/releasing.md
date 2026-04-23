# Releasing ImageGrab

This repo supports GitHub Releases that publish both a `.zip` and a `.dmg` for the app.

## Release modes

### Unsigned mode

If Apple secrets are not configured, the GitHub Actions release job still:

1. Builds the app bundle
2. Creates a `.zip`
3. Creates a drag-install `.dmg`
4. Uploads `.zip`, `.dmg`, and checksums to GitHub Releases

This is the best no-Apple-account distribution path. Users may need to right-click the app and choose **Open** on first launch, or remove the quarantine attribute manually.

### Signed and notarized mode

If Apple secrets are configured, the release flow additionally:

1. Builds the release app bundle.
2. Stamps the app with the release version and build number.
3. Signs the app with a `Developer ID Application` certificate and hardened runtime.
4. Notarizes the zipped app.
5. Staples the notarization ticket to the app.
6. Creates a drag-install `.dmg`.
7. Signs and notarizes the `.dmg`.
8. Uploads the `.zip`, `.dmg`, and checksums to GitHub Releases.

## Required GitHub Actions secrets for signed/notarized releases

- `DEVELOPER_ID_APPLICATION`
  Example: `Developer ID Application: Your Name (TEAMID)`
- `MACOS_CERTIFICATE_P12_BASE64`
  Base64-encoded `.p12` that contains the Developer ID Application cert and private key.
- `MACOS_CERTIFICATE_PASSWORD`
  Password for the `.p12`.
- `APPLE_API_KEY_ID`
  App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`
  App Store Connect issuer ID.
- `APPLE_API_PRIVATE_KEY`
  Full `.p8` key contents for `notarytool`.

## Creating a release

Tag the commit you want to ship and push the tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

That triggers `.github/workflows/release.yml`, which builds and publishes:

- `ImageGrab-0.1.0-macOS.zip`
- `ImageGrab-0.1.0.dmg`
- `SHA256SUMS`

If Apple secrets are absent, the workflow publishes an unsigned release and the GitHub Release notes include first-launch instructions for macOS Gatekeeper.

## Local dry run

Build unsigned local release artifacts:

```sh
SIGN_IDENTITY=none NOTARIZE=0 ./Scripts/build_release_assets.sh v0.1.0
```

Build signed and notarized local artifacts:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
APPLE_API_KEY_ID=... \
APPLE_API_ISSUER_ID=... \
APPLE_API_PRIVATE_KEY="$(cat ~/AuthKey_ABC123XYZ.p8)" \
./Scripts/build_release_assets.sh v0.1.0
```

Artifacts are written to `dist/<version>/`.

## Homebrew cask follow-on

Only do this once you are regularly shipping signed/notarized releases. A Homebrew cask does not solve Gatekeeper warnings for unsigned apps, so it is not the first move to optimize.

After a release artifact exists, generate a cask snippet:

```sh
./Scripts/generate_homebrew_cask.sh v0.1.0
```

That prints a cask using the release zip URL and the correct SHA-256 for that build.
