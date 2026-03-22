#!/usr/bin/env pwsh
# Export jellyfin-catalogue data to CSV
# Usage: .\export-csv.ps1 [-Type movies|tv|music|all]

param(
    [ValidateSet('movies', 'tv', 'music', 'all')]
    [string]$Type = 'all'
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$json = Get-Content "$scriptDir\catalogue.json" -Raw | ConvertFrom-Json
$outDir = $scriptDir

function Export-Movies($movies, $path) {
    $rows = foreach ($m in $movies) {
        $actor1 = if ($m.actors.Count -ge 1) { $m.actors[0] } else { '' }
        $actor2 = if ($m.actors.Count -ge 2) { $m.actors[1] } else { '' }
        [PSCustomObject]@{
            Title     = $m.name
            Year      = $m.year
            Duration  = if ($m.runtime) { "$($m.runtime) min" } else { '' }
            Rating    = $m.rating
            Actor1    = $actor1
            Actor2    = $actor2
            Director  = $m.director
            DateAdded = if ($m.dateAdded) { $m.dateAdded } else { '' }
        }
    }
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($rows.Count) movies to $path"
}

function Export-TV($series, $path) {
    $rows = foreach ($s in $series) {
        $actor1 = if ($s.actors.Count -ge 1) { $s.actors[0] } else { '' }
        $actor2 = if ($s.actors.Count -ge 2) { $s.actors[1] } else { '' }
        [PSCustomObject]@{
            Title     = $s.name
            Year      = $s.year
            Episodes  = $s.episodes
            Rating    = $s.rating
            Actor1    = $actor1
            Actor2    = $actor2
            Director  = $s.director
            DateAdded = if ($s.dateAdded) { $s.dateAdded } else { '' }
        }
    }
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($rows.Count) TV series to $path"
}

function Export-Music($albums, $path) {
    $rows = foreach ($a in $albums) {
        [PSCustomObject]@{
            Title     = $a.name
            Year      = $a.year
            Artist    = $a.artist
            DateAdded = if ($a.dateAdded) { $a.dateAdded } else { '' }
        }
    }
    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($rows.Count) music albums to $path"
}

if ($Type -eq 'movies' -or $Type -eq 'all') {
    Export-Movies $json.movies "$outDir\movies.csv"
}
if ($Type -eq 'tv' -or $Type -eq 'all') {
    Export-TV $json.tv "$outDir\tv.csv"
}
if ($Type -eq 'music' -or $Type -eq 'all') {
    Export-Music $json.music "$outDir\music.csv"
}
