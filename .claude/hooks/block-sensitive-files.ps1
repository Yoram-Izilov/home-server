$ErrorActionPreference = 'Stop'
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $cmd = $data.tool_input.command
    if (-not $cmd) { exit 0 }

    # Only inspect commands that START with `git add`. Intentionally narrow:
    # shell-level chaining ("cd foo && git add bar") is not handled, but the
    # alternative -- matching `git add` anywhere -- false-positives on commit
    # message bodies and echo strings that mention the phrase. Gitignored files
    # can't enter the index without an earlier `git add -f`, which this blocks.
    $trimmed = $cmd.Trim()
    if ($trimmed -notmatch '^git\s+add\b') { exit 0 }

    $patterns = @(
        @{ pattern = 'alertmanager[/\\]discord-webhook-url'; label = 'alertmanager/discord-webhook-url (Discord alert webhook)' },
        @{ pattern = '(^|[\s/\\])\.env(\s|$|[/\\])';          label = '.env (secrets)' },
        @{ pattern = '-webhook-url(\s|$)';                    label = '*-webhook-url (webhook secret)' },
        @{ pattern = '\.(key|pem)(\s|$)';                     label = 'private key (.key / .pem)' },
        @{ pattern = '\.htpasswd(\s|$)';                      label = '.htpasswd (basic-auth credentials)' }
    )
    foreach ($p in $patterns) {
        if ($trimmed -match $p.pattern) {
            [Console]::Error.WriteLine("BLOCKED: 'git add' references a gitignored / sensitive path: $($p.label)")
            [Console]::Error.WriteLine("These hold secrets (webhooks, keys, passwords) and must never be staged.")
            [Console]::Error.WriteLine("Stage specific safe files by name instead (e.g. git add monitoring/docker-compose.yml).")
            exit 2
        }
    }
    exit 0
} catch {
    exit 0
}
