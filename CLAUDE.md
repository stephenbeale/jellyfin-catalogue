# jellyfin-catalogue

Offline searchable catalogue of the Jellyfin media library (see README.md for
the feature overview and normal `export-catalogue.ps1` -> `catalogue.json` ->
GitHub Pages flow).

## Session Notes

### 2026-08-29 - Root-caused the silent export failure

**Work Completed:**
- Root-caused a month-long silent failure: Jellyfin 10.9 migrated its DB from
  `library.db` (old raw-SQLite schema) to `jellyfin.db` (new EF Core schema)
  on 2026-07-28. `export-catalogue.ps1` was still querying the old table
  names and had been failing silently ever since.
- Rewrote all 4 SQL queries against the new schema (`BaseItems`,
  `Peoples`/`PeopleBaseItemMap`, `MediaStreamInfos`). TV episode counts now
  join on the real `SeriesId` FK instead of fragile `SeriesName` text
  matching.
- Validated live against the real production database: 1124 movies, 98 TV
  series, 1480 music albums, spot-checked correct.
- Shipped as PR #8 (squash-merged to `master`).

**Unfinished Git Workflows:** none — `master` is clean, PR #8 merged, nothing
unpushed, no open PRs.

**Next Steps / Known Follow-ups (not done this session):**
1. `CHANGELOG.md` and `README.md` still describe the old `library.db` schema
   and stale counts (README: ~800 movies/76 TV/1295 albums; CHANGELOG:
   2026-03-01 entry) — both need an update reflecting the new schema and the
   real current counts (1124/98/1480).
2. The export script still fails **silently** on schema drift or DB errors —
   no alarm, no notification, no non-zero exit code. If Jellyfin changes its
   schema again, this could recur undetected for another month. Worth adding
   a hard failure/notification path.

**Technical Notes:**
- `export-csv.ps1` is a separate ad-hoc utility that reads `catalogue.json`
  (not the DB) and writes `movies.csv`/`tv.csv`/`music.csv` for spot-checking
  — these CSVs are regenerable local artifacts, not committed data, and are
  now covered by `.gitignore` (`*.csv`, added alongside this note after
  turning up untracked in a `git status` during session close-out).

### 2026-10-04 - Export committed to the checked-out branch, not master

- Live site stuck at 2026-07-28: the export's `git commit` went to the checked-out
  branch (`feature/music-track-listings`, unpushed) and `git push origin master`
  pushed nothing. Fixed with plumbing commits straight to master (see CHANGELOG).
- The `JellyfinCatalogueExport` scheduled task was found **disabled** (last run
  2026-10-04 09:36, result 0). It was left disabled: its action runs the main
  checkout's copy of the script, which is the feature branch with uncommitted work.
  Re-enable once that branch has merged master.


### 2026-11-08 - JF Catalogue: API exporter, offline PWA, Jellyfin plugin (PR #10)

**Work Completed (squash-merged as PR #10, tagged `plugin-v0.1.0`):**
- `export-catalogue-api.ps1`: exports via the Jellyfin REST API (API key) instead of
  SQLite. Exits 1 on any error, exits 2 and leaves `catalogue.json` alone on a >20% count
  drop (`-Force`), keeps the timestamp when nothing changed (no daily no-op commits).
  Git publish extracted to `publish-catalogue.ps1`, shared with the legacy exporter.
  This closes follow-up 2 from 2026-08-29 (silent failure) for the API path.
- Offline installable PWA: `sw.js`, `manifest.webmanifest`, `icons/`. App renamed
  **JF Catalogue** (not "Jellyfin ..." to avoid looking official; unaffiliated note in README).
- `plugin/`: Jellyfin plugin (C#, .NET 10 for Jellyfin 12.x, .NET 9 build for 10.11).
  Serves the PWA at `/JFCatalogue/<shareKey>/`, dashboard settings page, daily scheduled
  task "Rebuild JF Catalogue". `plugin/manifest.json` = plugin repository; workflow
  `.github/workflows/plugin.yml` builds on PRs and on a `plugin-v*` tag releases + updates
  the manifest on master (4th version digit = server line: .12 / .11).
- Tested against real Jellyfin 12.4.0 and 10.11.11 in Docker (`dockerd` + `jellyfin/jellyfin`
  image works in cloud sessions), including install from a plugin repo and offline use with
  the server stopped. Exporter and plugin output were identical on the same server.

**Next Steps / Known Follow-ups:**
1. Not yet done on real hardware: the exporter on Steve's server and Windows PowerShell 5.1;
   install + airplane mode on a real Android phone and iPhone; the plugin on Steve's server
   (check its Jellyfin version: 10.11+ required, 10.10 won't build).
2. `JellyfinCatalogueExport` scheduled task is still **disabled** (see 2026-10-04). If keeping
   the GitHub Pages site, point it at `export-catalogue-api.ps1 -Publish` with a
   `catalogue.config.json` and re-enable it. The main checkout is still on the unmerged
   `feature/music-track-listings` branch with uncommitted work.
3. README "Current library" counts were refreshed to 1217/99/1497; CHANGELOG is current.
   (Closes follow-up 1 from 2026-08-29.)
4. Ideas not started: barcode scanning in shops (possible paid tier), Plex/Emby support,
   name "Jolly Fine" (check Jellyfin naming guidance and availability first).

**Technical Notes:**
- Plugin page is anonymous by design (home-screen apps have no Jellyfin session); access is
  the 128-bit share key. jellyfin-web's custom-element polyfill throws on
  `document.createElement(name, { is })`, so the config page builds checkboxes via innerHTML.
- Release flow: push tag `plugin-vX.Y.Z` -> workflow builds 12.x + 10.11, creates the
  GitHub release, commits `plugin/manifest.json` to master. Users add
  `https://raw.githubusercontent.com/stephenbeale/jellyfin-catalogue/master/plugin/manifest.json`.
