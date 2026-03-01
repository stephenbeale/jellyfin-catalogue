# Changelog

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
