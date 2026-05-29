$ErrorActionPreference = 'Stop'
try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $data = $raw | ConvertFrom-Json
    $filePath = $data.tool_input.file_path
    if (-not $filePath) { exit 0 }

    $name = Split-Path -Leaf $filePath

    $lines = @()
    if ($name -in @('docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml')) {
        $lines += "  - keep the network named 'monitoring' and deploy with -p monitoring (resolves to monitoring_monitoring; the bot attaches externally)."
        $lines += "  - pin every image to an explicit version tag (no :latest)."
        $lines += "  - if you added a scraped service, add a matching scrape job in prometheus/prometheus.yml."
    }
    elseif ($name -eq 'prometheus.yml') {
        $lines += "  - every scrape target must resolve to a service on monitoring_monitoring (or host.docker.internal for host targets)."
        $lines += "  - rule_files glob is /etc/prometheus/rules/*.yml -- new rule files are picked up automatically."
        $lines += "  - the alertmanager target (alertmanager:9093) must match the alertmanager service."
    }
    elseif ($name -eq 'alertmanager.yml') {
        $lines += "  - never inline the Discord webhook URL -- use webhook_url_file: /etc/alertmanager/discord-webhook-url."
    }
    else { exit 0 }

    [Console]::Error.WriteLine("REMINDER: you edited $name. Monitoring invariants (see monitoring/CLAUDE.md):")
    foreach ($l in $lines) { [Console]::Error.WriteLine($l) }
    [Console]::Error.WriteLine("Run the sync-monitoring-config skill to audit.")
    exit 0
} catch {
    exit 0
}
