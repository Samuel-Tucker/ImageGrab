# Releasing ImageGrab

This repo now supports signed and notarized GitHub Releases that publish both a `.zip` and a `.dmg` for the app.

## What the release flow does

1. Builds the release app bundle.
2. Stamps the app with the release version and build number.
3. Signs the app with a `Developer ID Application` certificate and hardened runtime.
4. Notarizes the zipped app.
5. Staples the notarization ticket to the app.
6. Creates a drag-install `.dmg`.
7. Signs and notarizes the `.dmg`.
8. Uploads the `.zip`, `.dmg`, and checksums to GitHub Releases.

## Required GitHub Actions secrets

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

## Optional Homebrew cask follow-on

After a release artifact exists, generate a cask snippet:

```sh
./Scripts/generate_homebrew_cask.sh v0.1.0
```

That prints a cask using the release zip URL and the correct SHA-256 for that build.
