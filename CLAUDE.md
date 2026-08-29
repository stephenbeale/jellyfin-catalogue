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
