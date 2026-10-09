# Publishing Screener

The repository and feeds default to `acousland/Screener`. Set `SCREENER_REPO=owner/repository` when building and publishing if that changes. The apps embed these feed URLs, so an owner change requires rebuilding them.

## Signing identities

Developer ID Application signing and Apple notarization are required by the public-release script. Signing is performed locally using the login Keychain. No Apple signing credential is uploaded to GitHub by these scripts.

The initial Sparkle keypair is generated once with:

```sh
source scripts/swift-env.sh
swift scripts/init-update-key.swift
```

The public key goes in `Assets/update-public-key` and is embedded in both bundles. The private seed goes in `.secrets/sparkle-private-key` (mode 0600, ignored by git). Back up that seed in your secure credential store: future releases must use the same key. The initializer refuses to silently replace an existing public identity. Never commit or upload `.secrets/`.

Set `SCREENER_SPARKLE_KEY_FILE` to a restored private seed file if needed. The script calls the official Sparkle `sign_update` tool and verifies each archive and feed before publication.

## Prepare the release

1. Run the tests and the two-Mac checks in VALIDATION.md.
2. Update `VERSION` and `docs/release-notes.md`.
3. Ensure `security find-identity -v -p codesigning` shows a Developer ID Application certificate.
4. Store notarization credentials with `xcrun notarytool store-credentials` and choose that profile with `SCREENER_NOTARY_PROFILE`. The default is the owner's existing `renoir-notary` profile.
5. Run:

```sh
scripts/prepare-release.sh
```

This builds both arm64 apps, signs Sparkle's nested helpers correctly, notarizes/staples each bundle, creates separate ZIP downloads, signs the archives and appcasts, and writes checksums and a release manifest to `dist/`.

For local review without Developer ID credentials, `scripts/prepare-release.sh --development` produces ad hoc bundles and signed development archives. These are not notarized and cannot pass the publication script. They are never offered through the live feeds automatically.

## Publish

With a valid `gh` login and network access:

```sh
scripts/publish.sh
```

Commit source changes on `main` before publishing. For future versions, update `VERSION`, rebuild locally and publish again using the same Sparkle signing key; build numbers increase by default using the current Unix timestamp.

The script validates the bundles, notarization tickets, checksums and signed feeds first. It creates the public repository if necessary, pushes source, creates a draft preview release, uploads both archives/checksums, publishes it, and only then updates the live feeds. The source commit excludes build products and private credentials.

The checked-in empty feeds are bootstrap feeds; they contain no claimed release. Prepared feeds remain in `dist/feeds/` until publication succeeds. This prevents a feed from advertising missing downloads.

All compilation, tests, signing, notarization and release preparation run locally. There are no GitHub Actions workflows, and the publication script disables Actions on the repository before pushing source. GitHub hosts source, release downloads and the signed Sparkle feeds; no Apple or Sparkle signing secret is uploaded. The first release is labelled a preview; see validation for the limits of the current test coverage.
