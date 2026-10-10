# Omaguake Preview Generator

This directory contains all the templates, scripts, and component assets used to generate the high-resolution showcase banner ([`preview.png`](../preview.png)) for Omaguake.

## Files

- **`generate-preview.sh`**: Automated script that reads the version from `manifest.json`, populates `template.html`, and renders `preview.png` via Chromium headless.
- **`template.html`**: The HTML/CSS template defining the showcase layout, ambient glows, feature cards, and window overlays.
- **`term_capture.png`**: High-resolution cropped screenshot of the live Omaguake dropdown terminal showing multi-tab sessions and `fastfetch`.
- **`settings_capture.png`**: High-resolution cropped screenshot of the Omaguake configuration panel.

## Usage

### Re-render Preview for a New Version
When bumping the version in `manifest.json`, simply run:

```bash
./.preview/generate-preview.sh
```

This will automatically pick up the new version string from `manifest.json` and generate a fresh `preview.png` in the project root.

### Capture Live Assets & Re-render
To re-capture live screenshots from a running Omarchy session (via `grim`, `wtype`, and `omarchy-shell`):

```bash
./.preview/generate-preview.sh --capture
```
