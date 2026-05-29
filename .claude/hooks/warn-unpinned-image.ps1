$ErrorActionPreference = 'Stop'
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $filePath = $data.tool_input.file_path
    if (-not $filePath) { exit 0 }

    $name = Split-Path -Leaf $filePath
    if ($name -notin @('docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml')) { exit 0 }
    if (-not (Test-Path -LiteralPath $filePath)) { exit 0 }

    $offenders = @()
    foreach ($line in Get-Content -LiteralPath $filePath) {
        if ($line -match '^\s*image:\s*(.+?)\s*$') {
            $ref = $Matches[1].Trim().Trim('"', "'")
            if ($ref -match '@sha256:') { continue }              # pinned by digest
            $seg = ($ref -split '/')[-1]                          # last path segment
            if ($seg -notmatch ':') {
                $offenders += "$ref  (no tag -> resolves to :latest)"
            }
            elseif ($seg -match ':latest$') {
                $offenders += "$ref  (uses :latest)"
            }
        }
    }

    if ($offenders.Count -gt 0) {
        [Console]::Error.WriteLine("REMINDER: unpinned image(s) in ${name} -- this stack pins exact versions for reproducible deploys:")
        foreach ($o in $offenders) { [Console]::Error.WriteLine("  - $o") }
        [Console]::Error.WriteLine("Pin to an explicit version tag (e.g. prom/prometheus:v3.11.3).")
    }
    exit 0
} catch {
    exit 0
}
