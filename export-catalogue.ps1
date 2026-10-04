<#
.SYNOPSIS
    Exports Jellyfin library metadata to catalogue.json for the offline catalogue site.
.DESCRIPTION
    Reads the Jellyfin SQLite database (read-only) and extracts movies, TV series,
    and music albums into a JSON file. If the data has changed, commits and pushes
    to the GitHub repo so GitHub Pages stays current.
.NOTES
    Designed for Windows Task Scheduler. Uses the bundled sqlite3.exe in the repo.
#>

param(
    # Jellyfin 10.9 replaced the old raw-SQLite library.db (TypedBaseItems/People/mediastreams)
    # with a new EF Core schema in jellyfin.db (BaseItems/Peoples+PeopleBaseItemMap/MediaStreamInfos).
    # This script targets the new schema; library.db.old is the pre-migration file, kept by Jellyfin
    # for reference only and no longer updated.
    [string]$DbPath = 'C:\ProgramData\Jellyfin\Server\data\jellyfin.db',
    [string]$RepoDir = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite = Join-Path $RepoDir 'sqlite3.exe'
$outputFile = Join-Path $RepoDir 'catalogue.json'

if (-not (Test-Path $sqlite)) {
    Write-Error "sqlite3.exe not found at $sqlite"
    exit 1
}
if (-not (Test-Path $DbPath)) {
    Write-Error "Jellyfin database not found at $DbPath"
    exit 1
}

function Invoke-Sqlite {
    param([string]$Query)
    $result = & $sqlite -json -readonly $DbPath $Query 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "sqlite3 query failed: $result"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($result)) { return @() }
    return $result | ConvertFrom-Json
}

function Split-Genres {
    param([string]$raw)
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,@() }
    $list = @($raw -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    # Force single-element arrays to stay arrays in JSON output
    return ,$list
}

function Truncate-Overview {
    param([string]$text, [int]$maxLen = 200)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text.Length -le $maxLen) { return $text }
    return $text.Substring(0, $maxLen).TrimEnd() + '...'
}

# --- People lookup (actors & directors for movies and TV) ---
# Note: PeopleBaseItemMap.Role holds the on-screen character name for actors (e.g. "Queen Elizabeth I"),
# not the Actor/Director classification - that lives on Peoples.PersonType instead.
Write-Host 'Querying people (actors & directors)...'
$peopleRaw = Invoke-Sqlite @"
SELECT
    m.ItemId,
    p.Name,
    p.PersonType
FROM PeopleBaseItemMap m
JOIN Peoples p ON p.Id = m.PeopleId
JOIN BaseItems t ON t.Id = m.ItemId
WHERE p.PersonType IN ('Actor', 'Director')
  AND t.Type IN (
    'MediaBrowser.Controller.Entities.Movies.Movie',
    'MediaBrowser.Controller.Entities.TV.Series'
  )
ORDER BY m.ItemId, p.PersonType, m.ListOrder;
"@

$actorsMap = @{}
$directorMap = @{}
foreach ($p in $peopleRaw) {
    $id = $p.ItemId
    if ($p.PersonType -eq 'Actor') {
        if (-not $actorsMap.ContainsKey($id)) { $actorsMap[$id] = @() }
        if ($actorsMap[$id].Count -lt 5) {
            $actorsMap[$id] += $p.Name
        }
    } elseif ($p.PersonType -eq 'Director') {
        if (-not $directorMap.ContainsKey($id)) {
            $directorMap[$id] = $p.Name
        }
    }
}
Write-Host "  Loaded $($actorsMap.Count) items with actors, $($directorMap.Count) with directors"

# --- Movies ---
Write-Host 'Querying movies...'
$moviesRaw = Invoke-Sqlite @"
SELECT
    t.Id AS Id,
    t.Name,
    t.ProductionYear,
    t.Genres,
    t.OfficialRating,
    t.CommunityRating,
    t.RunTimeTicks,
    t.Overview,
    t.DateCreated,
    ms.Width AS ResWidth,
    ms.Height AS ResHeight
FROM BaseItems t
LEFT JOIN MediaStreamInfos ms ON ms.ItemId = t.Id AND ms.StreamType = 1 AND ms.StreamIndex = 0
WHERE t.Type = 'MediaBrowser.Controller.Entities.Movies.Movie'
  AND COALESCE(t.IsVirtualItem, 0) = 0
ORDER BY t.SortName;
"@

$movies = @()
foreach ($m in $moviesRaw) {
    $runtime = $null
    if ($m.RunTimeTicks) {
        $runtime = [math]::Round([long]$m.RunTimeTicks / 600000000)
    }
    $resolution = $null
    if ($m.ResWidth -and $m.ResHeight) {
        $resolution = "$($m.ResWidth)x$($m.ResHeight)"
    }
    $rating = $null
    if ($m.CommunityRating) {
        $rating = [math]::Round([double]$m.CommunityRating, 1)
    }
    $actors = if ($actorsMap.ContainsKey($m.Id)) { ,$actorsMap[$m.Id] } else { ,@() }
    $director = if ($directorMap.ContainsKey($m.Id)) { $directorMap[$m.Id] } else { $null }
    $dateAdded = if ($m.DateCreated) { ($m.DateCreated -replace ' ','T').Substring(0,10) } else { $null }
    $movies += [ordered]@{
        name       = $m.Name
        year       = $m.ProductionYear
        genres     = Split-Genres $m.Genres
        rating     = $rating
        cert       = if ($m.OfficialRating) { $m.OfficialRating } else { $null }
        runtime    = $runtime
        resolution = $resolution
        actors     = $actors
        director   = $director
        overview   = Truncate-Overview $m.Overview
        dateAdded  = $dateAdded
    }
}
Write-Host "  Found $($movies.Count) movies"

# --- TV Series ---
Write-Host 'Querying TV series...'
$tvRaw = Invoke-Sqlite @"
SELECT
    s.Id AS Id,
    s.Name,
    s.ProductionYear,
    s.Genres,
    s.OfficialRating,
    s.CommunityRating,
    s.Overview,
    s.DateCreated,
    (SELECT COUNT(*) FROM BaseItems e
     WHERE e.Type = 'MediaBrowser.Controller.Entities.TV.Episode'
       AND e.SeriesId = s.Id) AS EpisodeCount
FROM BaseItems s
WHERE s.Type = 'MediaBrowser.Controller.Entities.TV.Series'
ORDER BY s.SortName;
"@

$tv = @()
foreach ($s in $tvRaw) {
    $rating = $null
    if ($s.CommunityRating) {
        $rating = [math]::Round([double]$s.CommunityRating, 1)
    }
    $actors = if ($actorsMap.ContainsKey($s.Id)) { ,$actorsMap[$s.Id] } else { ,@() }
    $director = if ($directorMap.ContainsKey($s.Id)) { $directorMap[$s.Id] } else { $null }
    $dateAdded = if ($s.DateCreated) { ($s.DateCreated -replace ' ','T').Substring(0,10) } else { $null }
    $tv += [ordered]@{
        name      = $s.Name
        year      = $s.ProductionYear
        genres    = Split-Genres $s.Genres
        rating    = $rating
        cert      = if ($s.OfficialRating) { $s.OfficialRating } else { $null }
        episodes  = [int]$s.EpisodeCount
        actors    = $actors
        director  = $director
        overview  = Truncate-Overview $s.Overview
        dateAdded = $dateAdded
    }
}
Write-Host "  Found $($tv.Count) TV series"

# --- Music Albums ---
Write-Host 'Querying music albums...'
$musicRaw = Invoke-Sqlite @"
SELECT
    Name,
    ProductionYear,
    AlbumArtists,
    Genres,
    DateCreated
FROM BaseItems
WHERE Type = 'MediaBrowser.Controller.Entities.Audio.MusicAlbum'
ORDER BY SortName;
"@

$music = @()
foreach ($a in $musicRaw) {
    $albumName = if ($a.Name) { $a.Name.Trim() } else { '' }
    if ($albumName -eq '') { continue }
    $artist = $null
    if ($a.AlbumArtists) {
        $artist = ($a.AlbumArtists -split '\|')[0].Trim()
        if ($artist -eq '') { $artist = $null }
    }
    $dateAdded = if ($a.DateCreated) { ($a.DateCreated -replace ' ','T').Substring(0,10) } else { $null }
    $music += [ordered]@{
        name      = $albumName
        year      = $a.ProductionYear
        artist    = $artist
        genres    = Split-Genres $a.Genres
        dateAdded = $dateAdded
    }
}
Write-Host "  Found $($music.Count) music albums"

# --- Build output ---
$catalogue = [ordered]@{
    updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    movies  = $movies
    tv      = $tv
    music   = $music
}

$json = $catalogue | ConvertTo-Json -Depth 4 -Compress:$false
[System.IO.File]::WriteAllText($outputFile, $json, [System.Text.Encoding]::UTF8)
Write-Host "Wrote $outputFile"

# --- Git commit + push if changed ---
# Commits catalogue.json straight onto master with plumbing commands (a temporary
# index, commit-tree, update-ref), whatever branch is checked out and without
# touching the working tree or the real index. Previously it ran `git commit` on the
# current branch and then `git push origin master`: with a feature branch checked
# out, every daily update landed on that branch, the push sent nothing new, and the
# GitHub Pages site (served from master) silently stopped updating on 2026-07-28.
Push-Location $RepoDir
$tempIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("catalogue-index-" + [guid]::NewGuid().ToString('N'))
try {
    & git fetch -q origin master
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed (exit $LASTEXITCODE)" }
    # Build on whichever of local/remote master is newer, so a stale local master
    # can't make the push a non-fast-forward.
    $parent = (& git rev-parse origin/master).Trim()
    & git merge-base --is-ancestor $parent master
    if ($LASTEXITCODE -eq 0) { $parent = (& git rev-parse master).Trim() }

    $blob = (& git hash-object -w -- catalogue.json).Trim()
    $current = (& git rev-parse "${parent}:catalogue.json" 2>$null)
    if ($current -and $current.Trim() -eq $blob) {
        Write-Host 'No changes to catalogue.json, skipping commit.'
    } else {
        Write-Host 'catalogue.json changed, committing to master...'
        $env:GIT_INDEX_FILE = $tempIndex
        & git read-tree $parent
        & git update-index --add --cacheinfo "100644,$blob,catalogue.json"
        $tree = (& git write-tree).Trim()
        Remove-Item Env:GIT_INDEX_FILE
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $commit = (& git commit-tree $tree -p $parent -m "Update catalogue $timestamp").Trim()
        & git push -q origin "${commit}:refs/heads/master"
        if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)" }
        # Fast-forward local master too, unless it holds commits of its own. If master
        # is checked out, re-sync the index entry so catalogue.json doesn't show as modified.
        & git merge-base --is-ancestor master $commit
        if ($LASTEXITCODE -eq 0) {
            & git update-ref refs/heads/master $commit
            if ((& git rev-parse --abbrev-ref HEAD).Trim() -eq 'master') { & git reset -q -- catalogue.json }
        }
        Write-Host "Pushed $($commit.Substring(0, 7)) to origin/master"
    }
} finally {
    if (Test-Path Env:GIT_INDEX_FILE) { Remove-Item Env:GIT_INDEX_FILE }
    Remove-Item -LiteralPath $tempIndex -ErrorAction SilentlyContinue
    Pop-Location
}
