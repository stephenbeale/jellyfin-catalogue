# Jellyfin Catalogue

Offline searchable catalogue of my Jellyfin media library. Designed for checking what I already own from my phone while out shopping for DVDs/Blu-rays — even when the Jellyfin server is off.

**Live site:** https://stephenbeale.github.io/jellyfin-catalogue/

## Features

- **Movies / TV / Music tabs** with item counts
- **Instant search** across titles, artists, and genres
- **Sort** by name (A-Z) or year (newest first)
- **Card layout** with metadata badges (cert, rating, runtime, resolution, episode count)
- **Mobile-first** dark theme — designed for phone screens
- **Auto-updated** daily via Windows Scheduled Task

## How it works

```
library.db --> export-catalogue.ps1 --> catalogue.json --> git push --> GitHub Pages
 (Jellyfin)     (Task Scheduler)         (in repo)                     (phone browser)
```

1. `export-catalogue.ps1` reads the Jellyfin SQLite database using the bundled `sqlite3.exe`
2. Extracts movies, TV series, and music albums into `catalogue.json`
3. If the data has changed, commits and pushes to GitHub
4. GitHub Pages serves the updated `index.html` which loads `catalogue.json`

## Files

| File | Description |
|---|---|
| `index.html` | Single-file HTML/CSS/JS catalogue page |
| `export-catalogue.ps1` | PowerShell script — reads DB, outputs JSON, auto-pushes |
| `catalogue.json` | Generated data (not manually edited) |
| `sqlite3.exe` | Portable SQLite binary (no system install needed) |
| `qr.html` | QR code page for quick phone access |

## Auto-update schedule

A Windows Scheduled Task (`JellyfinCatalogueExport`) runs daily at **06:00**. If the Jellyfin library has changed, the catalogue is regenerated and pushed automatically.

To run manually:

```powershell
.\export-catalogue.ps1
```

## Current library

- ~800 movies
- ~76 TV series
- ~1295 music albums
