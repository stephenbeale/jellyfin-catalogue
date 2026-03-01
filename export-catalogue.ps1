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
    [string]$DbPath = 'C:\ProgramData\Jellyfin\Server\data\library.db',
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
Write-Host 'Querying people (actors & directors)...'
$peopleRaw = Invoke-Sqlite @"
SELECT
    p.ItemId,
    p.Name,
    p.PersonType
FROM People p
JOIN TypedBaseItems t ON t.guid = p.ItemId
WHERE p.PersonType IN ('Actor', 'Director')
  AND t.type IN (
    'MediaBrowser.Controller.Entities.Movies.Movie',
    'MediaBrowser.Controller.Entities.TV.Series'
  )
ORDER BY p.ItemId, p.PersonType, p.ListOrder;
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
    t.guid AS Id,
    t.Name,
    t.ProductionYear,
    t.Genres,
    t.OfficialRating,
    t.CommunityRating,
    t.RunTimeTicks,
    t.Overview,
    ms.Width AS ResWidth,
    ms.Height AS ResHeight
FROM TypedBaseItems t
LEFT JOIN mediastreams ms ON ms.ItemId = t.guid AND ms.StreamType = 'Video' AND ms.StreamIndex = 0
WHERE t.type = 'MediaBrowser.Controller.Entities.Movies.Movie'
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
    }
}
Write-Host "  Found $($movies.Count) movies"

# --- TV Series ---
Write-Host 'Querying TV series...'
$tvRaw = Invoke-Sqlite @"
SELECT
    s.guid AS Id,
    s.Name,
    s.ProductionYear,
    s.Genres,
    s.OfficialRating,
    s.CommunityRating,
    s.Overview,
    (SELECT COUNT(*) FROM TypedBaseItems e
     WHERE e.type = 'MediaBrowser.Controller.Entities.TV.Episode'
       AND e.SeriesName = s.Name) AS EpisodeCount
FROM TypedBaseItems s
WHERE s.type = 'MediaBrowser.Controller.Entities.TV.Series'
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
    $tv += [ordered]@{
        name     = $s.Name
        year     = $s.ProductionYear
        genres   = Split-Genres $s.Genres
        rating   = $rating
        cert     = if ($s.OfficialRating) { $s.OfficialRating } else { $null }
        episodes = [int]$s.EpisodeCount
        actors   = $actors
        director = $director
        overview = Truncate-Overview $s.Overview
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
    Genres
FROM TypedBaseItems
WHERE type = 'MediaBrowser.Controller.Entities.Audio.MusicAlbum'
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
    $music += [ordered]@{
        name   = $albumName
        year   = $a.ProductionYear
        artist = $artist
        genres = Split-Genres $a.Genres
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
Push-Location $RepoDir
try {
    $status = & git status --porcelain -- catalogue.json 2>&1
    if ($status) {
        Write-Host 'catalogue.json changed, committing...'
        & git add catalogue.json
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        & git commit -m "Update catalogue $timestamp"
        & git push origin master
        Write-Host 'Pushed to origin/master'
    } else {
        Write-Host 'No changes to catalogue.json, skipping commit.'
    }
} finally {
    Pop-Location
}
