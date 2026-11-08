# Changelog

## 2026-11-08 - Offline, installable phone app

- **Added:** the site is now an installable web app that works with no signal. `sw.js` (service worker) keeps the page and `catalogue.json` on the phone. The catalogue is network-first with a 4-second timeout, falling back to the saved copy, so weak shop signal doesn't leave a blank screen. A yellow banner shows when the saved copy is in use and when it was exported.
- Added `manifest.webmanifest` and icons (`icons/`, PNGs whitelisted in `.gitignore`), with an **Install app** button on Android/Chrome and **Use offline** instructions on iPhone.
- The app is now called **JF Catalogue** (page title, header, home-screen name), with "for Jellyfin" used only to describe what it works with, and an unaffiliated note in the README. This avoids looking like an official Jellyfin product.
- `qr.html` now builds the QR code for whatever URL it's served from, instead of a hardcoded GitHub Pages address, so copies of the site work too.
- Tested in Chromium with phone emulation, served under `/jellyfin-catalogue/` as on GitHub Pages: installable (no installability errors). With the network offline, all 1217 movies render and search works. A 9-second catalogue response falls back to the saved copy at about 4.5s. Not yet tried on a real phone.

## 2026-11-08 - API-based exporter (works on any Jellyfin install)

- **Added:** `export-catalogue-api.ps1` reads the library over the Jellyfin REST API with an API key, instead of querying the server's SQLite database. Jellyfin upgrades that change the internal schema (as 10.9 did on 2026-07-28) no longer break the export. It runs on Windows PowerShell 5.1 and PowerShell 7 (Windows/Linux/macOS), against local, Docker, NAS or remote servers, with no `sqlite3.exe` or DB file access.
- Configured by parameter, environment variable (`JELLYFIN_URL`, `JELLYFIN_API_KEY`) or a gitignored `catalogue.config.json`. Optional `-UserId` and `-Library` filters.
- **Fails loudly:** exits 1 on any error with a specific message (bad key, server unreachable, unknown library, git failure). Exits 2 and leaves `catalogue.json` untouched if any category drops by more than 20% (`-MaxDropPercent`, override with `-Force`). Writes via a temp file.
- When nothing changed, the previous `updated` timestamp is kept so the file is byte-identical and no commit is made. Previously every run committed, because the timestamp always changed.
- TV episode counts now exclude missing (virtual) episodes, so they count files you actually have.
- Extracted the git plumbing publish step into `publish-catalogue.ps1`, shared by both exporters (`-Publish` on the API exporter). Behaviour unchanged.
- Tested against a mock Jellyfin server generated from the current `catalogue.json`: output matched the existing catalogue item-for-item (1217 movies, 99 series, 1497 albums), with paging, null-field omission, virtual items and library filters exercised. Publishing tested in a throwaway repo with a feature branch checked out. Not yet run against the real server, and not yet run on Windows PowerShell 5.1.
- README updated for the new setup, and library counts refreshed.

## 2026-10-04 - Catalogue updates reach the live site again

- **Fixed:** the GitHub Pages site had shown the 2026-07-28 catalogue ever since. `export-catalogue.ps1` committed `catalogue.json` on whatever branch was checked out, then ran `git push origin master`. With `feature/music-track-listings` checked out, every daily update (30+ commits) landed on that unpushed branch, and the push sent nothing.
- The export now commits `catalogue.json` straight onto master with git plumbing (temporary index, `commit-tree`, push of the new commit to `refs/heads/master`), whichever branch is checked out. The working tree and real index are left alone. It builds on the newer of local/remote master. Local master is fast-forwarded only if it has no commits of its own. Fetch or push failures now throw instead of passing silently.
- Tested in a throwaway repo: with a feature branch checked out, the commit lands on master and the feature branch and its uncommitted changes are untouched. An unchanged catalogue makes no commit. With master checked out, the working tree stays clean.

## 2026-03-01 — Initial release

- Created `export-catalogue.ps1` — reads Jellyfin `library.db` via bundled `sqlite3.exe`
- Extracts 800 movies, 76 TV series, 1295 music albums
- Created `index.html` — mobile-first dark-themed catalogue with:
  - Movies / TV / Music tabs with counts
  - Instant search (title, artist, genre)
  - A-Z and Year sort toggle
  - Card layout with cert, rating, runtime, resolution, episode count badges
  - Truncated overview text for movies and TV
- Added `qr.html` — QR code page for quick phone access
- Set up Windows Scheduled Task `JellyfinCatalogueExport` — runs daily at 06:00
- Enabled GitHub Pages on `master` branch
- Fixed PS5.1 single-element array collapse for genres (`,@()` trick + JS `Array.isArray()` guard)
- Filtered blank-name music albums; cleaned pipe-separated `AlbumArtists` to first artist
