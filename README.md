# Jellyfin Catalogue

Offline searchable catalogue of a Jellyfin media library. Designed for checking what you already own from your phone while out shopping for DVDs/Blu-rays, even when the Jellyfin server is off.

**Live site:** https://stephenbeale.github.io/jellyfin-catalogue/

## Features

- **Movies / TV / Music tabs** with item counts
- **Instant search** across titles, artists, and genres
- **Sort** by name (A-Z) or year (newest first)
- **Card layout** with metadata badges (cert, rating, runtime, resolution, episode count)
- **Mobile-first** dark theme, designed for phone screens
- **Works offline:** install it to your home screen and it keeps working with no signal, using the copy saved on the phone
- **Auto-updated** daily on a schedule

## How it works

```
Jellyfin server --> export-catalogue-api.ps1 --> catalogue.json --> git push --> GitHub Pages
  (REST API)          (scheduled daily)           (in repo)                     (phone browser)
```

1. `export-catalogue-api.ps1` asks the Jellyfin server for its movies, TV series, and music albums over the REST API, using an API key
2. Writes them to `catalogue.json`
3. With `-Publish`, commits `catalogue.json` to `master` and pushes it if the library changed
4. GitHub Pages serves `index.html`, which loads `catalogue.json`

Because it uses the public API rather than Jellyfin's internal database, it keeps working across Jellyfin upgrades and runs anywhere PowerShell does: Windows, Linux, macOS, or next to a Docker or NAS install. The server can be on another machine.

## Setup

1. **Create an API key:** Jellyfin Dashboard > API Keys > `+`. Name it e.g. `catalogue`.
2. **Configure:** copy `catalogue.config.example.json` to `catalogue.config.json` (gitignored) and fill in `serverUrl` and `apiKey`. Or set the `JELLYFIN_URL` and `JELLYFIN_API_KEY` environment variables, or pass `-ServerUrl` / `-ApiKey`.
3. **Run it:**

   ```powershell
   ./export-catalogue-api.ps1            # writes catalogue.json
   ./export-catalogue-api.ps1 -Publish   # ...and commits + pushes it to master
   ```

   Windows PowerShell 5.1 (built into Windows) and PowerShell 7+ both work. On Linux/macOS, install PowerShell 7 and run it with `pwsh`.

### Options

| Setting | Parameter | Env var | Config key | Default |
|---|---|---|---|---|
| Server URL | `-ServerUrl` | `JELLYFIN_URL` | `serverUrl` | (required) |
| API key | `-ApiKey` | `JELLYFIN_API_KEY` | `apiKey` | (required) |
| Only what one user can see | `-UserId` | `JELLYFIN_USER_ID` | `userId` | whole server |
| Only some libraries | `-Library 'Movies','TV Shows'` | | `libraries` | all |

Other switches: `-OutputFile`, `-PageSize`, `-MaxDropPercent` (default 20), `-Force`.

### Failure handling

The export is meant to fail loudly, not silently:

- **Exit 1** on any error: server unreachable, API key rejected, unknown library, git push failed. The message says what to fix.
- **Exit 2** if any category shrinks by more than `-MaxDropPercent` compared with the existing `catalogue.json`. The old file is left untouched, so a wrong key or library setting can't wipe the site. Re-run with `-Force` if the drop is real.
- If nothing changed, the file is left byte-identical and no commit is made.

Point your scheduler's "on failure" alerting at the exit code.

## Using it on your phone

1. Open the site once with a connection. The catalogue is saved on the phone from then on.
2. Add it to your home screen:
   - **Android (Chrome):** tap **Install app** at the bottom of the page, or menu > *Install app*
   - **iPhone (Safari):** Share > *Add to Home Screen* (the **Use offline** button explains this)
3. In a shop with no signal, it opens from the saved copy and a yellow banner shows when that copy was exported. If the signal is weak, it waits up to 4 seconds for fresh data and then falls back to the saved copy.

Each time you open it with a connection, it picks up the latest export.

## Files

| File | Description |
|---|---|
| `index.html` | Single-file HTML/CSS/JS catalogue page |
| `export-catalogue-api.ps1` | Exporter: Jellyfin REST API to `catalogue.json` |
| `publish-catalogue.ps1` | Commits `catalogue.json` straight onto `master` and pushes, whatever branch is checked out |
| `catalogue.config.example.json` | Template for `catalogue.config.json` |
| `catalogue.json` | Generated data (not manually edited) |
| `qr.html` | QR code page for quick phone access (points at whichever site it's served from) |
| `sw.js` | Service worker: offline caching of the page and catalogue |
| `manifest.webmanifest`, `icons/` | Makes the site installable as a home-screen app |
| `export-catalogue.ps1` | Legacy exporter: reads Jellyfin's SQLite DB directly (needs `sqlite3.exe` and local DB access; breaks on schema changes). Kept until the API exporter has replaced it in the scheduled task. |
| `sqlite3.exe` | Portable SQLite binary for the legacy exporter |

## Auto-update schedule

A Windows Scheduled Task (`JellyfinCatalogueExport`) runs daily at **06:00**. To switch it to the API exporter, set its action to:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<repo>\export-catalogue-api.ps1" -Publish
```

with the API key in `catalogue.config.json`, so it doesn't appear on the command line.

On Linux, a cron entry does the same:

```
0 6 * * * cd /path/to/jellyfin-catalogue && pwsh -NoProfile -File export-catalogue-api.ps1 -Publish
```

## Current library

- 1217 movies
- 99 TV series
- 1497 music albums
