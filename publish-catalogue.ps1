<#
.SYNOPSIS
    Commits catalogue.json straight onto master and pushes it, if it changed.
.DESCRIPTION
    Shared by export-catalogue-api.ps1 and export-catalogue.ps1. Uses git plumbing
    (a temporary index, commit-tree, update-ref), so it works whatever branch is
    checked out and never touches the working tree or the real index.

    Background: the export used to run `git commit` on the current branch and then
    `git push origin master`. With a feature branch checked out, every daily update
    landed on that branch, the push sent nothing new, and the GitHub Pages site
    (served from master) silently stopped updating on 2026-07-28.

    Throws on any git failure, so callers exit non-zero.
#>
[CmdletBinding()]
param(
    [string]$RepoDir = $PSScriptRoot,
    [string]$Branch = 'master'
)

$ErrorActionPreference = 'Stop'

Push-Location $RepoDir
$tempIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("catalogue-index-" + [guid]::NewGuid().ToString('N'))
try {
    & git fetch -q origin $Branch
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed (exit $LASTEXITCODE)" }
    # Build on whichever of local/remote branch is newer, so a stale local branch
    # can't make the push a non-fast-forward.
    $parent = (& git rev-parse "origin/$Branch").Trim()
    & git merge-base --is-ancestor $parent $Branch
    if ($LASTEXITCODE -eq 0) { $parent = (& git rev-parse $Branch).Trim() }

    $blob = (& git hash-object -w -- catalogue.json).Trim()
    $current = (& git rev-parse "${parent}:catalogue.json" 2>$null)
    if ($current -and $current.Trim() -eq $blob) {
        Write-Host 'No changes to catalogue.json, skipping commit.'
        return
    }

    Write-Host "catalogue.json changed, committing to $Branch..."
    $env:GIT_INDEX_FILE = $tempIndex
    & git read-tree $parent
    & git update-index --add --cacheinfo "100644,$blob,catalogue.json"
    $tree = (& git write-tree).Trim()
    Remove-Item Env:GIT_INDEX_FILE
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $commit = (& git commit-tree $tree -p $parent -m "Update catalogue $timestamp").Trim()
    & git push -q origin "${commit}:refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)" }
    # Fast-forward the local branch too, unless it holds commits of its own. If it
    # is checked out, re-sync the index entry so catalogue.json doesn't show as modified.
    & git merge-base --is-ancestor $Branch $commit
    if ($LASTEXITCODE -eq 0) {
        & git update-ref "refs/heads/$Branch" $commit
        if ((& git rev-parse --abbrev-ref HEAD).Trim() -eq $Branch) { & git reset -q -- catalogue.json }
    }
    Write-Host "Pushed $($commit.Substring(0, 7)) to origin/$Branch"
} finally {
    if (Test-Path Env:GIT_INDEX_FILE) { Remove-Item Env:GIT_INDEX_FILE }
    Remove-Item -LiteralPath $tempIndex -ErrorAction SilentlyContinue
    Pop-Location
}
