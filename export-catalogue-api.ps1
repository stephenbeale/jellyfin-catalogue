<#
.SYNOPSIS
    Exports a Jellyfin library to catalogue.json using the Jellyfin REST API.
.DESCRIPTION
    Talks to the Jellyfin server over HTTP with an API key instead of reading its
    SQLite database. This means:
      - no breakage when Jellyfin changes its internal DB schema (as 10.9 did)
      - works with any install: Windows, Linux, Docker, NAS, or a remote server
      - no sqlite3.exe and no file access to the server needed

    Produces the same catalogue.json shape as export-catalogue.ps1, so index.html
    is unchanged.

    Fails loudly: any error exits non-zero (1), and a suspicious drop in item counts
    compared with the existing catalogue.json refuses to overwrite it (exit 2)
    unless -Force is given.

    Runs on Windows PowerShell 5.1 and PowerShell 7+ (Windows, Linux, macOS).

.PARAMETER ServerUrl
    Jellyfin base URL, e.g. http://localhost:8096. Falls back to $env:JELLYFIN_URL,
    then serverUrl in the config file.
.PARAMETER ApiKey
    API key from Jellyfin Dashboard > API Keys. Falls back to $env:JELLYFIN_API_KEY,
    then apiKey in the config file. Prefer the env var or config file so the key
    doesn't appear in scheduled-task command lines.
.PARAMETER UserId
    Optional. Export what this Jellyfin user can see, instead of the whole server.
.PARAMETER Library
    Optional. Names of the libraries to include (e.g. 'Movies','TV Shows'). Default: all.
.PARAMETER ConfigFile
    Optional JSON config: { "serverUrl": "...", "apiKey": "...", "userId": "...", "libraries": [...] }.
    Default: catalogue.config.json next to this script (gitignored).
.PARAMETER MaxDropPercent
    Refuse to overwrite catalogue.json if any category shrinks by more than this
    percentage. Guards against a misconfigured key or library silently wiping the site.
.PARAMETER Force
    Overwrite even if the drop guard trips.
.PARAMETER Publish
    After writing, commit catalogue.json to master and push (see publish-catalogue.ps1).

.EXAMPLE
    $env:JELLYFIN_URL = 'http://localhost:8096'; $env:JELLYFIN_API_KEY = '...'
    ./export-catalogue-api.ps1 -Publish
#>
[CmdletBinding()]
param(
    [string]$ServerUrl,
    [string]$ApiKey,
    [string]$UserId,
    [string[]]$Library,
    [string]$OutputFile = (Join-Path $PSScriptRoot 'catalogue.json'),
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'catalogue.config.json'),
    [ValidateRange(1, 10000)][int]$PageSize = 500,
    [ValidateRange(0, 100)][int]$MaxDropPercent = 20,
    [switch]$Force,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-RestMethod progress bars are very slow on 5.1

$ExitFailure = 1
$ExitDropGuard = 2

# Jellyfin omits null fields from its JSON, so read optional properties defensively.
function Get-Field {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-FirstNonEmpty {
    foreach ($v in $args) { if (-not [string]::IsNullOrWhiteSpace([string]$v)) { return $v } }
    return $null
}

function Limit-Text {
    param([string]$Text, [int]$MaxLen = 200)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen).TrimEnd() + '...'
}

function ConvertTo-DateOnly {
    param($Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    # Invoke-RestMethod on PS7 turns ISO strings into DateTime; on 5.1 they stay strings.
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-dd') }
    return ([string]$Value).Substring(0, 10)
}

function Get-Rating {
    param($Value)
    if ($null -eq $Value -or [double]$Value -eq 0) { return $null }
    return [math]::Round([double]$Value, 1)
}

# Returns a plain object[] so single-element lists stay JSON arrays (PS5.1 unrolls otherwise).
function Get-Genres {
    param($Item)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($g in @(Get-Field $Item 'Genres')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$g)) { $list.Add(([string]$g).Trim()) }
    }
    return , $list.ToArray()
}

function Get-People {
    param($Item)
    $actors = New-Object System.Collections.Generic.List[object]
    $director = $null
    foreach ($p in @(Get-Field $Item 'People')) {
        $type = Get-Field $p 'Type'
        $name = Get-Field $p 'Name'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($type -eq 'Actor' -and $actors.Count -lt 5) { $actors.Add($name) }
        elseif ($type -eq 'Director' -and -not $director) { $director = $name }
    }
    return @{ Actors = $actors.ToArray(); Director = $director }
}

function Invoke-Jellyfin {
    param([string]$Path, [hashtable]$Query = @{})
    $pairs = foreach ($k in ($Query.Keys | Sort-Object)) {
        '{0}={1}' -f $k, [uri]::EscapeDataString([string]$Query[$k])
    }
    $uri = $script:BaseUrl + $Path
    if ($pairs) { $uri += '?' + ($pairs -join '&') }
    try {
        return Invoke-RestMethod -Uri $uri -Headers $script:Headers -Method Get -TimeoutSec 300 -UseBasicParsing
    } catch {
        $status = $null
        $resp = Get-Field $_.Exception 'Response'
        if ($resp) { $status = [int]$resp.StatusCode }
        $hint = switch ($status) {
            401 { ' (API key rejected - check it in Dashboard > API Keys)' }
            403 { ' (API key lacks permission)' }
            404 { ' (endpoint not found - is the URL pointing at Jellyfin?)' }
            default { '' }
        }
        throw "GET $Path failed$hint`: $($_.Exception.Message)"
    }
}

# Pages through /Items, once per selected library (or once for the whole server).
function Get-AllItems {
    param([hashtable]$Query)
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($parentId in $script:ParentIds) {
        $start = 0
        do {
            $q = @{} + $Query
            $q['Recursive'] = 'true'
            $q['StartIndex'] = $start
            $q['Limit'] = $script:PageSize
            $q['EnableImages'] = 'false'
            $q['EnableUserData'] = 'false'
            if ($parentId) { $q['ParentId'] = $parentId }
            if ($script:UserIdResolved) { $q['userId'] = $script:UserIdResolved }
            $page = Invoke-Jellyfin '/Items' $q
            $items = @(Get-Field $page 'Items')
            $total = [int](Get-Field $page 'TotalRecordCount')
            foreach ($i in $items) {
                if ((Get-Field $i 'LocationType') -ne 'Virtual') { $all.Add($i) }
            }
            $start += $items.Count
        } while ($items.Count -gt 0 -and $start -lt $total)
    }
    # Libraries can overlap (mixed-content folders), so de-duplicate by Id.
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($i in $all) {
        $id = Get-Field $i 'Id'
        if ($id -and $seen.ContainsKey($id)) { continue }
        if ($id) { $seen[$id] = $true }
        $unique.Add($i)
    }
    return , $unique.ToArray()
}

function Get-CategoryCounts {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $old = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
        return @{
            movies = @(Get-Field $old 'movies').Count
            tv     = @(Get-Field $old 'tv').Count
            music  = @(Get-Field $old 'music').Count
        }
    } catch {
        Write-Warning "Existing $Path is unreadable, skipping drop guard: $($_.Exception.Message)"
        return $null
    }
}

try {
    # --- Resolve configuration: parameter > environment variable > config file ---
    $config = $null
    if ($ConfigFile -and (Test-Path -LiteralPath $ConfigFile)) {
        $config = [System.IO.File]::ReadAllText($ConfigFile) | ConvertFrom-Json
        Write-Host "Using config file $ConfigFile"
    }
    $ServerUrl = Get-FirstNonEmpty $ServerUrl $env:JELLYFIN_URL (Get-Field $config 'serverUrl')
    $ApiKey = Get-FirstNonEmpty $ApiKey $env:JELLYFIN_API_KEY (Get-Field $config 'apiKey')
    $UserId = Get-FirstNonEmpty $UserId $env:JELLYFIN_USER_ID (Get-Field $config 'userId')
    if (-not $Library) { $Library = @(Get-Field $config 'libraries') | Where-Object { $_ } }

    if (-not $ServerUrl) { throw 'No server URL. Pass -ServerUrl, set JELLYFIN_URL, or add serverUrl to the config file.' }
    if (-not $ApiKey) { throw 'No API key. Create one in Jellyfin Dashboard > API Keys, then pass -ApiKey, set JELLYFIN_API_KEY, or add apiKey to the config file.' }

    # Windows PowerShell 5.1 defaults to TLS 1.0, which modern reverse proxies refuse.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    $script:BaseUrl = $ServerUrl.TrimEnd('/')
    $script:PageSize = $PageSize
    $script:UserIdResolved = $UserId
    $script:Headers = @{
        Authorization = "MediaBrowser Client=`"jellyfin-catalogue`", Device=`"export`", DeviceId=`"jellyfin-catalogue-export`", Version=`"1.0.0`", Token=`"$ApiKey`""
    }

    # --- Connect (also validates the key) ---
    $info = Invoke-Jellyfin '/System/Info'
    Write-Host "Connected to $(Get-Field $info 'ServerName') (Jellyfin $(Get-Field $info 'Version'))"

    # --- Library selection ---
    $script:ParentIds = @($null)
    if ($Library) {
        # Invoke-RestMethod emits a JSON array as one object; pipe it to unroll.
        $folders = @(Invoke-Jellyfin '/Library/VirtualFolders' | ForEach-Object { $_ })
        $script:ParentIds = @(foreach ($name in $Library) {
            $match = $folders | Where-Object { (Get-Field $_ 'Name') -eq $name } | Select-Object -First 1
            if (-not $match) {
                $available = ($folders | ForEach-Object { Get-Field $_ 'Name' }) -join ', '
                throw "Library '$name' not found. Available: $available"
            }
            Get-Field $match 'ItemId'
        })
        Write-Host "Libraries: $($Library -join ', ')"
    }

    # --- Movies ---
    Write-Host 'Fetching movies...'
    $movies = New-Object System.Collections.Generic.List[object]
    foreach ($m in (Get-AllItems @{ IncludeItemTypes = 'Movie'; SortBy = 'SortName'; SortOrder = 'Ascending'
                                    Fields = 'Genres,People,Overview,DateCreated,MediaStreams' })) {
        $runtime = $null
        $ticks = Get-Field $m 'RunTimeTicks'
        if ($ticks) { $runtime = [int][math]::Round([long]$ticks / 600000000) }
        $resolution = $null
        $video = @(Get-Field $m 'MediaStreams') | Where-Object { (Get-Field $_ 'Type') -eq 'Video' } | Select-Object -First 1
        if ($video -and (Get-Field $video 'Width') -and (Get-Field $video 'Height')) {
            $resolution = "$(Get-Field $video 'Width')x$(Get-Field $video 'Height')"
        }
        $people = Get-People $m
        $movies.Add([ordered]@{
            name       = Get-Field $m 'Name'
            year       = Get-Field $m 'ProductionYear'
            genres     = Get-Genres $m
            rating     = Get-Rating (Get-Field $m 'CommunityRating')
            cert       = Get-FirstNonEmpty (Get-Field $m 'OfficialRating')
            runtime    = $runtime
            resolution = $resolution
            actors     = $people.Actors
            director   = $people.Director
            overview   = Limit-Text (Get-Field $m 'Overview')
            dateAdded  = ConvertTo-DateOnly (Get-Field $m 'DateCreated')
        })
    }
    Write-Host "  Found $($movies.Count) movies"

    # --- Episode counts per series (real files only; missing/virtual episodes excluded) ---
    Write-Host 'Counting TV episodes...'
    $episodeCounts = @{}
    foreach ($e in (Get-AllItems @{ IncludeItemTypes = 'Episode'; IsMissing = 'false' })) {
        $sid = Get-Field $e 'SeriesId'
        if (-not $sid) { continue }
        if ($episodeCounts.ContainsKey($sid)) { $episodeCounts[$sid]++ } else { $episodeCounts[$sid] = 1 }
    }

    # --- TV series ---
    Write-Host 'Fetching TV series...'
    $tv = New-Object System.Collections.Generic.List[object]
    foreach ($s in (Get-AllItems @{ IncludeItemTypes = 'Series'; SortBy = 'SortName'; SortOrder = 'Ascending'
                                    Fields = 'Genres,People,Overview,DateCreated' })) {
        $id = Get-Field $s 'Id'
        $people = Get-People $s
        $tv.Add([ordered]@{
            name      = Get-Field $s 'Name'
            year      = Get-Field $s 'ProductionYear'
            genres    = Get-Genres $s
            rating    = Get-Rating (Get-Field $s 'CommunityRating')
            cert      = Get-FirstNonEmpty (Get-Field $s 'OfficialRating')
            episodes  = if ($episodeCounts.ContainsKey($id)) { [int]$episodeCounts[$id] } else { 0 }
            actors    = $people.Actors
            director  = $people.Director
            overview  = Limit-Text (Get-Field $s 'Overview')
            dateAdded = ConvertTo-DateOnly (Get-Field $s 'DateCreated')
        })
    }
    Write-Host "  Found $($tv.Count) TV series"

    # --- Music albums ---
    Write-Host 'Fetching music albums...'
    $music = New-Object System.Collections.Generic.List[object]
    foreach ($a in (Get-AllItems @{ IncludeItemTypes = 'MusicAlbum'; SortBy = 'SortName'; SortOrder = 'Ascending'
                                    Fields = 'Genres,DateCreated' })) {
        $albumName = ([string](Get-Field $a 'Name')).Trim()
        if ($albumName -eq '') { continue }
        $firstArtist = @(Get-Field $a 'AlbumArtists') | Select-Object -First 1
        $artist = Get-FirstNonEmpty (Get-Field $a 'AlbumArtist') (Get-Field $firstArtist 'Name')
        if ($artist) { $artist = ([string]$artist).Trim() }
        $music.Add([ordered]@{
            name      = $albumName
            year      = Get-Field $a 'ProductionYear'
            artist    = $artist
            genres    = Get-Genres $a
            dateAdded = ConvertTo-DateOnly (Get-Field $a 'DateCreated')
        })
    }
    Write-Host "  Found $($music.Count) music albums"

    # --- Sanity checks before overwriting anything ---
    $new = @{ movies = $movies.Count; tv = $tv.Count; music = $music.Count }
    if (($new.movies + $new.tv + $new.music) -eq 0) {
        throw 'The server returned no movies, TV series or albums. Check the API key, -UserId and -Library settings.'
    }
    $old = Get-CategoryCounts $OutputFile
    if ($old -and -not $Force) {
        $drops = foreach ($k in 'movies', 'tv', 'music') {
            if ($old[$k] -ge 10) {
                $pct = [math]::Round(100 * ($old[$k] - $new[$k]) / $old[$k])
                if ($pct -gt $MaxDropPercent) { "$k $($old[$k]) -> $($new[$k]) (-$pct%)" }
            }
        }
        if ($drops) {
            Write-Host "Refusing to overwrite $OutputFile, item counts dropped by more than ${MaxDropPercent}%: $($drops -join '; ')" -ForegroundColor Red
            Write-Host 'If this is expected, re-run with -Force.' -ForegroundColor Red
            exit $ExitDropGuard
        }
    }

    # --- Write (to a temp file first, so a crash never leaves a half-written catalogue) ---
    $catalogue = [ordered]@{
        updated = $null
        movies  = $movies.ToArray()
        tv      = $tv.ToArray()
        music   = $music.ToArray()
    }
    # If nothing in the library changed, keep the previous timestamp: the file stays
    # byte-identical and -Publish makes no commit, instead of one commit every day.
    $unchanged = $false
    if (Test-Path -LiteralPath $OutputFile) {
        $oldText = [System.IO.File]::ReadAllText($OutputFile)
        if ($oldText -match '"updated":\s*"([^"]+)"') {
            $catalogue.updated = $Matches[1]
            $unchanged = (ConvertTo-Json -InputObject $catalogue -Depth 5) -eq $oldText
        }
    }
    if ($unchanged) {
        Write-Host "No library changes since $($catalogue.updated), $OutputFile left as is."
    } else {
        $catalogue.updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $json = ConvertTo-Json -InputObject $catalogue -Depth 5
        $tmp = "$OutputFile.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $OutputFile -Force
        Write-Host "Wrote $OutputFile"
    }

    if ($Publish) {
        $repoCatalogue = Join-Path $PSScriptRoot 'catalogue.json'
        if ([System.IO.Path]::GetFullPath($OutputFile) -ne [System.IO.Path]::GetFullPath($repoCatalogue)) {
            throw "-Publish only works when writing the repo's own catalogue.json ($repoCatalogue)."
        }
        & (Join-Path $PSScriptRoot 'publish-catalogue.ps1') -RepoDir $PSScriptRoot
    }
} catch {
    Write-Host "Export failed: $($_.Exception.Message)" -ForegroundColor Red
    exit $ExitFailure
}
exit 0
