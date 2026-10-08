# WebSSH one-command installer and manager for Windows.
#
# Mirrors install.sh: it prepares a deployment directory with a generated
# application secret, an .env file, and a docker-compose.yml, then starts the
# published image through Docker Desktop.
#
# The script is idempotent: re-running it keeps the existing deployment
# directory, generated application secret, and TLS settings.
#
# Commands:
#   install         (default) install and start WebSSH
#   upgrade         pull the newest release and restart the container
#   port            change the published web port
#   reset-password  reset the password of a local account
#   status          show the container state and the readiness probe
#   uninstall       stop the container and remove the installation
#
# Usage:
#   .\install.ps1
#   .\install.ps1 -Port 8443 -Tls self-signed -Domain webssh.lan
#   .\install.ps1 -Command port -Port 9000
#   .\install.ps1 -Command reset-password -Username admin
#   .\install.ps1 -Command uninstall -Purge -Yes

[CmdletBinding()]
param(
    [ValidateSet(
        'install',
        'upgrade',
        'port',
        'reset-password',
        'status',
        'uninstall'
    )]
    [string]$Command = 'install',

    [ValidateSet('docker')]
    [string]$Mode = 'docker',

    [string]$Dir = '.\webssh-deployment',

    [ValidateRange(1, 65535)]
    [int]$Port = 5000,

    [ValidateSet('off', 'self-signed', 'manual', 'acme')]
    [string]$Tls = 'off',

    [string]$Domain = '',

    [string]$Email = '',

    [string]$Username = '',

    [string]$PasswordFile = '',

    [switch]$Generate,

    [switch]$AllowInternalSsh,

    [switch]$NoStart,

    [switch]$NoPull,

    [switch]$Purge,

    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Image = 'ghcr.io/zhengwuji/web-ssh:latest'
$ReadyTimeoutSeconds = 120
$ServiceName = 'webssh'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')

function Write-Step {
    param([string]$Message)
    Write-Host $Message
}

function Write-WarningLine {
    param([string]$Message)
    Write-Warning $Message
}

function Stop-Install {
    param([string]$Message)
    Write-Error "ERROR: $Message"
    exit 1
}

function Get-EnvValue {
    param([string]$Path, [string]$Key)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^$([regex]::Escape($Key))=(.+)$") {
            return $Matches[1]
        }
    }
    return $null
}

function New-Secret {
    $bytes = New-Object 'byte[]' 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Get-ExistingSecret {
    param([string]$Path)

    $value = Get-EnvValue -Path $Path -Key 'SECRET_KEY'
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    if ($value -in @('changeme', 'secret', 'your-secret-key', '<your-secret-key>')) {
        return $null
    }
    return $value
}

function Get-BlockInternalSsh {
    if ($AllowInternalSsh) { return 'false' }
    return 'true'
}

function Get-SecureCookies {
    if ($Tls -eq 'off') { return 'false' }
    return 'true'
}

function Get-Origins {
    if ($Tls -eq 'off') {
        return "http://localhost:$Port,http://127.0.0.1:$Port"
    }
    # Engine.IO validates the Origin header against CORS_ORIGINS, so the real
    # TLS hostname has to be listed or every browser connection is rejected.
    $Origins = "https://localhost:$Port,https://127.0.0.1:$Port"
    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        $Origins += ",https://${Domain}:$Port"
        if ($Port -eq 443) {
            $Origins += ",https://$Domain"
        }
    }
    return $Origins
}

function Test-DockerOrStop {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Stop-Install 'Docker Desktop is required. Install it from https://docs.docker.com/desktop/.'
    }
    docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Stop-Install 'Docker Compose v2 is required (docker compose version failed).'
    }
}

function Invoke-DockerCompose {
    param([string[]]$Arguments, [switch]$AllowFailure)

    Push-Location -LiteralPath $InstallDir
    try {
        & docker compose @Arguments
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0 -and -not $AllowFailure) {
        Stop-Install "docker compose $($Arguments -join ' ') failed."
    }
    return $code
}

function Get-Scheme {
    if ($Tls -eq 'off') { return 'http' }
    return 'https'
}

function Wait-ForReadiness {
    $ReadyUrl = "$(Get-Scheme)://localhost:$Port/ready"
    Write-Step "Waiting for $ReadyUrl ..."
    $Deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
    while ((Get-Date) -lt $Deadline) {
        try {
            Invoke-WebRequest -Uri $ReadyUrl -TimeoutSec 3 -UseBasicParsing *> $null
            Write-Step "WebSSH is ready at $(Get-Scheme)://localhost:$Port"
            return
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    Write-WarningLine "The readiness endpoint did not answer within ${ReadyTimeoutSeconds}s."
    Write-WarningLine 'Inspect the container logs before exposing this instance.'
}

function Write-DeploymentFiles {
    $Stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    $EnvLines = @(
        "# Generated by install.ps1 on $Stamp",
        "SECRET_KEY=$Script:Secret",
        'DEPLOYMENT_PROFILE=homelab',
        '# Published host port. The container always listens on 5000, so this',
        '# key is installer metadata and is not read by the application.',
        "WEBSSH_HOST_PORT=$Port",
        "CORS_ORIGINS=$(Get-Origins)",
        'ALLOW_CORS_WILDCARD=false',
        "BLOCK_INTERNAL_SSH=$(Get-BlockInternalSsh)",
        "WEBSSH_TLS_MODE=$Tls"
    )
    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        $EnvLines += "WEBSSH_TLS_DOMAIN=$Domain"
    }
    if (-not [string]::IsNullOrWhiteSpace($Email)) {
        $EnvLines += "WEBSSH_TLS_EMAIL=$Email"
    }
    Set-Content -LiteralPath $EnvFile -Value $EnvLines -Encoding utf8NoBOM

    $ComposeLines = @(
        "# Generated by install.ps1 on $Stamp",
        '# Edit .env, then run: docker compose up -d',
        '',
        'services:',
        '  webssh:',
        "    image: $Image",
        "    container_name: $ServiceName",
        '    restart: unless-stopped',
        '    stop_grace_period: 40s',
        '    env_file:',
        '      - .env',
        '    environment:',
        '      - PORT=5000',
        '      - TRUSTED_PROXIES=0',
        "      - SESSION_COOKIE_SECURE=$(Get-SecureCookies)",
        '      - TMUX_ENABLED=true',
        '      - TMUX_DEFAULT=true',
        '      - TMUX_SESSION_PREFIX=webssh',
        '      - BACKUP_TEMP_DIR=/app/recovery',
        '      - BACKUP_RECOVERY_DURABLE=true',
        '    ports:',
        "      - `"$Port`:5000`""
    )
    if ($Tls -eq 'acme' -and $Port -ne 80) {
        # The ACME standalone challenge needs host port 80. Skip it when the
        # chosen application port already binds 80, a duplicate mapping.
        $ComposeLines += '      - "80:80"'
    }
    $ComposeLines += @(
        '    volumes:',
        '      - webssh_data:/app/data',
        '      - webssh_recovery:/app/recovery',
        '    healthcheck:',
        '      test: ["CMD", "python", "healthcheck.py"]',
        '      interval: 30s',
        '      timeout: 5s',
        '      retries: 3',
        '      start_period: 10s',
        '',
        'volumes:',
        '  webssh_data:',
        '  webssh_recovery:',
        '    driver: local'
    )
    Set-Content -LiteralPath $ComposeFile -Value $ComposeLines -Encoding utf8NoBOM
}

function Confirm-Action {
    param([string]$Message)

    if ($Yes) { return $true }
    if (-not [Environment]::UserInteractive) { return $false }
    try {
        $reply = Read-Host "$Message [y/N]"
    } catch {
        return $false
    }
    return ($reply -match '^(y|Y|yes|YES)$')
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

if ($Tls -in @('self-signed', 'acme') -and [string]::IsNullOrWhiteSpace($Domain)) {
    Stop-Install "-Domain is required for -Tls $Tls."
}
if ($Tls -eq 'acme' -and [string]::IsNullOrWhiteSpace($Email)) {
    Stop-Install '-Email is required for -Tls acme.'
}
if ($Command -ne 'reset-password') {
    if (-not [string]::IsNullOrWhiteSpace($Username) -or
        -not [string]::IsNullOrWhiteSpace($PasswordFile) -or
        $Generate) {
        Stop-Install '-Username, -PasswordFile, and -Generate require -Command reset-password.'
    }
}
if ($Command -eq 'reset-password' -and [string]::IsNullOrWhiteSpace($Username)) {
    Stop-Install '-Username is required for -Command reset-password.'
}
if ($Command -eq 'port' -and -not $PortExplicit) {
    Stop-Install '-Port is required for -Command port.'
}

$InstallDir = New-Item -ItemType Directory -Force -Path $Dir |
    Select-Object -ExpandProperty FullName
$EnvFile = Join-Path $InstallDir '.env'
$ComposeFile = Join-Path $InstallDir 'docker-compose.yml'

if ($Command -ne 'install') {
    # Reuse the settings the deployment was created with.
    $existing = Get-EnvValue -Path $EnvFile -Key 'WEBSSH_TLS_MODE'
    if (-not [string]::IsNullOrWhiteSpace($existing)) { $Tls = $existing }
    $existing = Get-EnvValue -Path $EnvFile -Key 'WEBSSH_TLS_DOMAIN'
    if (-not [string]::IsNullOrWhiteSpace($existing)) { $Domain = $existing }
    $existing = Get-EnvValue -Path $EnvFile -Key 'WEBSSH_TLS_EMAIL'
    if (-not [string]::IsNullOrWhiteSpace($existing)) { $Email = $existing }
    $existing = Get-EnvValue -Path $EnvFile -Key 'BLOCK_INTERNAL_SSH'
    if ($existing -eq 'false') { $AllowInternalSsh = $true }
    if (-not $PortExplicit) {
        $existing = Get-EnvValue -Path $EnvFile -Key 'WEBSSH_HOST_PORT'
        if ([string]::IsNullOrWhiteSpace($existing)) {
            $existing = Get-EnvValue -Path $EnvFile -Key 'PORT'
        }
        if (-not [string]::IsNullOrWhiteSpace($existing)) { $Port = [int]$existing }
    }
}

$Script:Secret = Get-ExistingSecret -Path $EnvFile
if ([string]::IsNullOrWhiteSpace($Script:Secret)) {
    $Script:Secret = New-Secret
}

Write-Step 'WebSSH installer'
Write-Step "Command: $Command"

switch ($Command) {
    'status' {
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            Write-Step "No deployment found in $InstallDir."
            exit 0
        }
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Write-WarningLine 'Docker is not installed; cannot inspect the container.'
            exit 0
        }
        Write-Step "Install directory: $InstallDir"
        Write-Step "Port: $Port | TLS: $Tls"
        Invoke-DockerCompose -Arguments @('ps') -AllowFailure | Out-Null
        if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
            $ReadyUrl = "$(Get-Scheme)://localhost:$Port/ready"
            try {
                Invoke-WebRequest -Uri $ReadyUrl -TimeoutSec 5 -UseBasicParsing *> $null
                Write-Step "Readiness: $ReadyUrl answered OK"
            } catch {
                Write-WarningLine "Readiness: $ReadyUrl did not answer."
            }
        }
        exit 0
    }
    'uninstall' {
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            Write-Step "No deployment found in $InstallDir."
            exit 0
        }
        if ($Purge) {
            Write-WarningLine "This removes WebSSH and ALL application data in $InstallDir."
        }
        if (-not (Confirm-Action "Remove WebSSH from ${InstallDir}?")) {
            Stop-Install 'Aborted. Re-run with -Yes to confirm in a non-interactive shell.'
        }
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            Write-Step 'Stopping the container...'
            if ($Purge) {
                Invoke-DockerCompose -Arguments @('down', '-v') -AllowFailure | Out-Null
            } else {
                Invoke-DockerCompose -Arguments @('down') -AllowFailure | Out-Null
            }
        }
        Write-Step 'Removing installation files...'
        Remove-Item -LiteralPath $ComposeFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $EnvFile -Force -ErrorAction SilentlyContinue
        if ($Purge) {
            $DataDir = Join-Path $InstallDir 'data'
            if (Test-Path -LiteralPath $DataDir) {
                Remove-Item -LiteralPath $DataDir -Recurse -Force
            }
        } else {
            Write-Step "Application data kept in $(Join-Path $InstallDir 'data') (use -Purge to delete it)."
        }
        Write-Step 'WebSSH has been uninstalled.'
        Write-Step 'Done.'
        exit 0
    }
    'reset-password' {
        Test-DockerOrStop
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            Stop-Install "No deployment found in $InstallDir."
        }
        $composeArgs = @('exec', '-T', $ServiceName, 'python', '-m', 'flask',
            '--app', 'start:app', 'reset-password', '--username', $Username)
        if ($Generate) {
            $composeArgs += '--generate'
        } elseif (-not [string]::IsNullOrWhiteSpace($PasswordFile)) {
            if (-not (Test-Path -LiteralPath $PasswordFile)) {
                Stop-Install "Password file not found: $PasswordFile"
            }
            $composeArgs += '--password-stdin'
        }
        Push-Location -LiteralPath $InstallDir
        try {
            if (-not [string]::IsNullOrWhiteSpace($PasswordFile)) {
                Get-Content -LiteralPath $PasswordFile -Raw |
                    & docker compose @composeArgs
            } else {
                & docker compose @composeArgs
            }
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($code -ne 0) {
            Stop-Install 'Password reset failed.'
        }
        Write-Step 'Done.'
        exit 0
    }
    'port' {
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            Stop-Install "No deployment found in $InstallDir."
        }
        Write-Step "Changing the WebSSH port to $Port..."
        if ([string]::IsNullOrWhiteSpace($Script:Secret)) {
            $Script:Secret = New-Secret
        }
        Write-DeploymentFiles
        if (-not $NoStart) {
            Test-DockerOrStop
            Invoke-DockerCompose -Arguments @('up', '-d') | Out-Null
            Wait-ForReadiness
        }
        Write-Step "WebSSH now listens on port $Port."
        Write-Step 'Done.'
        exit 0
    }
    'upgrade' {
        if (-not (Test-Path -LiteralPath $ComposeFile)) {
            Stop-Install "No deployment found in $InstallDir."
        }
        Test-DockerOrStop
        if (-not $NoPull) {
            Write-Step 'Pulling the newest WebSSH image...'
            Invoke-DockerCompose -Arguments @('pull', '--quiet') | Out-Null
        }
        Invoke-DockerCompose -Arguments @('up', '-d') | Out-Null
        Wait-ForReadiness
        Write-Step 'Upgrade finished.'
        Write-Step 'Done.'
        exit 0
    }
}

# install
Test-DockerOrStop
Write-Step "Mode: $Mode | Port: $Port | TLS: $Tls"
Write-DeploymentFiles

if ($NoStart) {
    Write-Step "Prepared $InstallDir (not started)."
    Write-Step "Start it later with: cd `"$InstallDir`"; docker compose up -d"
    exit 0
}

if (-not $NoPull) {
    Write-Step 'Pulling the WebSSH image...'
    Invoke-DockerCompose -Arguments @('pull', '--quiet') -AllowFailure |
        Out-Null
}

Write-Step 'Starting WebSSH...'
Invoke-DockerCompose -Arguments @('up', '-d') | Out-Null

Wait-ForReadiness

Write-Step "Install directory: $InstallDir"
Write-Step "Follow logs with: cd `"$InstallDir`"; docker compose logs -f"
Write-Step "Change the port with: .\install.ps1 -Command port -Port PORT"
Write-Step "Reset a password with: .\install.ps1 -Command reset-password -Username NAME"
Write-Step 'Done.'
