# Changelog

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
