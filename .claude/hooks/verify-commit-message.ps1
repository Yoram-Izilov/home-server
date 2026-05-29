$ErrorActionPreference = 'Stop'
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $cmd = $data.tool_input.command
    if (-not $cmd) { exit 0 }

    # Anchor to start of command so this hook does not false-positive when
    # other commands (e.g. `gh pr create --body "..."`) mention "git commit"
    # in a quoted body.
    $trimmed = $cmd.Trim()
    if ($trimmed -notmatch '^git\s+commit\b') { exit 0 }
    $cmd = $trimmed

    $hasMessage = ($cmd -match '\s-m\b') -or ($cmd -match '\s--message\b')
    if (-not $hasMessage) { exit 0 }

    $msg = $null

    $heredocRe = [regex]'(?s)<<\s*[''"]?EOF[''"]?\s*\r?\n(.*?)\r?\n\s*EOF'
    $hd = $heredocRe.Match($cmd)
    if ($hd.Success) {
        $msg = $hd.Groups[1].Value.Trim()
    }
    elseif ($cmd -match '-m\s+"([^"]+)"') {
        $msg = $Matches[1]
    }
    elseif ($cmd -match "-m\s+'([^']+)'") {
        $msg = $Matches[1]
    }
    elseif ($cmd -match '-m\s+(\S+)') {
        $msg = $Matches[1]
    }

    if (-not $msg) { exit 0 }

    $subject = ($msg -split "`n", 2)[0].Trim()

    $pattern = '^(feat|fix|refactor|chore|docs|style)\((monitoring|prometheus|grafana|loki|tempo|promtail|alertmanager|pyroscope|compose|jenkins|nginx|docs)\):\s+.+'
    if ($subject -notmatch $pattern) {
        [Console]::Error.WriteLine("BLOCKED: commit subject does not match CLAUDE.md format.")
        [Console]::Error.WriteLine("Got:      $subject")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Required: <type>(<scope>): <subject in imperative mood>")
        [Console]::Error.WriteLine("  type:   feat | fix | refactor | chore | docs | style")
        [Console]::Error.WriteLine("  scope:  monitoring | prometheus | grafana | loki | tempo | promtail | alertmanager | pyroscope | compose | jenkins | nginx | docs")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Example: feat(prometheus): add scrape target + alerts for the portfolio container")
        exit 2
    }
    exit 0
} catch {
    exit 0
}
