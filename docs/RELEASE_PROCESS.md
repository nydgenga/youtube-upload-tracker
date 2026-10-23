# Development builds and releases

This repository uses two GitHub Actions workflows:

- `.github/workflows/validate.yml` runs on pushes, pull requests, and manual invocation. When `package/` and `tests/` exist, it executes Python/JavaScript regression checks and uploads an installable `.plasmoid` as a **development artifact**, not a public release.
- `.github/workflows/release.yml` runs **only when `.github/release-request.json` is added or changed on main**. It requires `approved: true`, a stable version number, nonempty release notes, and exactly matching `package/metadata.json`. The workflow reruns tests before publishing a GitHub Release and attaching the built package.

## Initial source import

The current widget code is `v0.1.0-dev15`. Import the **contents** of the development source ZIP into the repository root, retaining the `package/` and `tests/` directories. Do not upload the ZIP as a single source file.

Once imported, the validation workflow should run its full regression suite and upload a development package in **Actions → latest run → Artifacts**.

## Release approval

A development build is not a release. Do not create `.github/release-request.json` until desktop testing is complete and the user explicitly approves publication.

For an approved stable version, update `package/metadata.json` and the changelog, run tests, then commit `.github/release-request.json` with the form:

```json
{
  "approved": true,
  "version": "1.0.0",
  "notes": "Release notes for this tested and approved version."
}
```

The publish workflow uses GitHub's temporary `GITHUB_TOKEN` with `contents: write` and does not need a personal access token. A duplicate version is rejected rather than overwritten. Repository Actions permissions must permit workflow write access.

**Policy:** Only a user-approved release may be published. Keep development artifacts separate from public releases. Refer to the KDE Plasma Widget Development methodology in the shared ChatGPT Project.
