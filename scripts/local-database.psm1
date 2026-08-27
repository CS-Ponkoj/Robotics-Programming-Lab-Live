Set-StrictMode -Version Latest

$script:DefaultProjectName = "robotics-lab-local"
$script:DefaultDatabaseName = "robotics_lab"
$script:DefaultDatabaseUser = "robotics"
$script:DefaultDatabasePassword = "robotics-local-only"
$script:DefaultDatabasePort = 5432

function Save-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = Join-Path $parent ((Split-Path -Leaf $Path) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-LocalDatabaseConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [int]$DatabasePort = $script:DefaultDatabasePort,
        [string]$ProjectName = $script:DefaultProjectName,
        [string]$BackupRoot = "",
        [string]$RuntimeRoot = ""
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
        $BackupRoot = Get-RoboticsDatabaseBackupRoot -RepositoryRoot $root
    }
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
        Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
        $RuntimeRoot = Get-RoboticsRuntimeRoot -RepositoryRoot $root
    }
    $password = if ([string]::IsNullOrWhiteSpace($env:ROBOTICS_LOCAL_DB_PASSWORD)) {
        $script:DefaultDatabasePassword
    } else {
        $env:ROBOTICS_LOCAL_DB_PASSWORD
    }
    $escapedUser = [uri]::EscapeDataString($script:DefaultDatabaseUser)
    $escapedPassword = [uri]::EscapeDataString($password)
    return [pscustomobject]@{
        RepositoryRoot = $root
        ComposeFile = Join-Path $root "docker-compose.yml"
        ProjectName = $ProjectName
        DatabaseName = $script:DefaultDatabaseName
        DatabaseUser = $script:DefaultDatabaseUser
        DatabasePassword = $password
        DatabasePort = $DatabasePort
        DatabaseUrl = "postgresql+psycopg://${escapedUser}:${escapedPassword}@127.0.0.1:${DatabasePort}/$($script:DefaultDatabaseName)"
        BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
        RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot)
    }
}

function Invoke-RoboticsCompose {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Quiet
    )

    $previous = @{}
    $environment = @{
        LOCAL_POSTGRES_DB = $Configuration.DatabaseName
        LOCAL_POSTGRES_USER = $Configuration.DatabaseUser
        LOCAL_POSTGRES_PASSWORD = $Configuration.DatabasePassword
        LOCAL_POSTGRES_PORT = [string]$Configuration.DatabasePort
    }
    foreach ($key in $environment.Keys) {
        $previous[$key] = [System.Environment]::GetEnvironmentVariable($key, "Process")
        [System.Environment]::SetEnvironmentVariable($key, $environment[$key], "Process")
    }
    try {
        $command = @(
            "compose",
            "--project-name", $Configuration.ProjectName,
            "--file", $Configuration.ComposeFile
        ) + $Arguments
        $output = @(& docker @command 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose command failed: $($output -join [Environment]::NewLine)"
        }
        if (-not $Quiet -and $output.Count -gt 0) {
            $output | Out-Host
        }
        return $output
    } finally {
        foreach ($key in $environment.Keys) {
            [System.Environment]::SetEnvironmentVariable($key, $previous[$key], "Process")
        }
    }
}

function Wait-ForLocalPostgres {
    param([Parameter(Mandatory = $true)]$Configuration)

    $consecutiveReadyChecks = 0
    for ($attempt = 1; $attempt -le 120; $attempt++) {
        try {
            Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                "exec", "-T", "postgres", "pg_isready",
                "-U", $Configuration.DatabaseUser,
                "-d", $Configuration.DatabaseName
            ) | Out-Null
            $consecutiveReadyChecks++
            if ($consecutiveReadyChecks -ge 3) { return }
        } catch {
            $consecutiveReadyChecks = 0
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Local PostgreSQL did not become healthy. Open Docker Desktop and review 'docker compose logs postgres'."
}

function Test-LocalPostgresApplicationSchema {
    param([Parameter(Mandatory = $true)]$Configuration)

    $result = Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
        "exec", "-T", "postgres", "psql",
        "-U", $Configuration.DatabaseUser,
        "-d", $Configuration.DatabaseName,
        "-At", "-c",
        "SELECT CASE WHEN to_regclass('public.alembic_version') IS NOT NULL AND to_regclass('public.users') IS NOT NULL THEN 'present' ELSE 'missing' END;"
    )
    return ((@($result) | Select-Object -Last 1).ToString().Trim() -eq "present")
}

function Export-PostgresDump {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $containerDump = "/tmp/robotics-lab-$([guid]::NewGuid().ToString('N')).dump"
    $destinationParent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    try {
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "exec", "-T", "postgres", "pg_dump",
            "-U", $Configuration.DatabaseUser,
            "-d", $Configuration.DatabaseName,
            "--format=custom", "--no-owner", "--no-privileges",
            "--file=$containerDump"
        ) | Out-Null
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "exec", "-T", "postgres", "pg_restore", "--list", $containerDump
        ) | Out-Null
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "cp", "postgres:$containerDump", $Destination
        ) | Out-Null
        if (-not (Test-Path -LiteralPath $Destination) -or (Get-Item -LiteralPath $Destination).Length -le 0) {
            throw "PostgreSQL created an empty or missing backup file."
        }
    } finally {
        try {
            Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                "exec", "-T", "postgres", "rm", "-f", $containerDump
            ) | Out-Null
        } catch {
            Write-Warning "The temporary PostgreSQL backup file could not be removed from the container."
        }
    }
}

function Get-PostgresChangePosition {
    param([Parameter(Mandatory = $true)]$Configuration)

    $result = Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
        "exec", "-T", "postgres", "psql",
        "-U", $Configuration.DatabaseUser,
        "-d", $Configuration.DatabaseName,
        "-At", "-c",
        "SELECT system_identifier::text || '|' || pg_current_wal_lsn()::text FROM pg_control_system();"
    )
    $value = (@($result) | Select-Object -Last 1).ToString().Trim()
    $parts = $value.Split('|', 2)
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "PostgreSQL did not return a valid database change position."
    }
    return [pscustomobject]@{
        SystemIdentifier = $parts[0]
        WalLsn = $parts[1]
    }
}

function Get-BackupMutexName {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $bytes = [Text.Encoding]::UTF8.GetBytes(
        [System.IO.Path]::GetFullPath($RepositoryRoot).ToLowerInvariant()
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $key = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 24)
    } finally {
        $sha.Dispose()
    }
    return "Local\RoboticsLabDatabaseBackup-$key"
}

function Save-RoboticsLocalPostgresBackup {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [int]$DatabasePort = $script:DefaultDatabasePort,
        [string]$ProjectName = $script:DefaultProjectName,
        [string]$BackupRoot = "",
        [string]$RuntimeRoot = "",
        [switch]$SkipIfUnchanged,
        [int]$MutexTimeoutSeconds = 30
    )

    $configuration = Get-LocalDatabaseConfiguration `
        -RepositoryRoot $RepositoryRoot `
        -DatabasePort $DatabasePort `
        -ProjectName $ProjectName `
        -BackupRoot $BackupRoot `
        -RuntimeRoot $RuntimeRoot
    $lockPath = Join-Path $configuration.BackupRoot "active-device.json"
    $lock = Read-JsonFile -Path $lockPath
    $device = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { "unknown-windows-device" } else { $env:COMPUTERNAME }
    if (-not $lock -or $lock.device -ne $device -or $lock.session_id -ne $SessionId) {
        throw "The local database lock does not belong to this application session. The backup was not changed."
    }

    $mutex = [Threading.Mutex]::new($false, (Get-BackupMutexName -RepositoryRoot $configuration.RepositoryRoot))
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexTimeoutSeconds))
        } catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw "Another database backup is still running. No backup files were changed."
        }

        Wait-ForLocalPostgres -Configuration $configuration
        $changePosition = Get-PostgresChangePosition -Configuration $configuration
        $autoStatePath = Join-Path $configuration.RuntimeRoot "database-auto-backup.json"
        $autoState = Read-JsonFile -Path $autoStatePath
        if (
            $SkipIfUnchanged -and
            $autoState -and
            $autoState.system_identifier -eq $changePosition.SystemIdentifier -and
            $autoState.wal_lsn -eq $changePosition.WalLsn
        ) {
            return [pscustomobject]@{
                Saved = $false
                Reason = "unchanged"
                Path = Join-Path $configuration.BackupRoot "latest.dump"
            }
        }

        $temporaryDump = Join-Path $configuration.RuntimeRoot "database-backup-$([guid]::NewGuid().ToString('N')).dump"
        try {
            Export-PostgresDump -Configuration $configuration -Destination $temporaryDump
            $hash = (Get-FileHash -LiteralPath $temporaryDump -Algorithm SHA256).Hash
            $size = (Get-Item -LiteralPath $temporaryDump).Length
            $schemaOutput = Invoke-RoboticsCompose -Configuration $configuration -Quiet -Arguments @(
                "exec", "-T", "postgres", "psql",
                "-U", $configuration.DatabaseUser,
                "-d", $configuration.DatabaseName,
                "-At", "-c", "SELECT version_num FROM alembic_version LIMIT 1;"
            )
            $schemaVersion = (@($schemaOutput) | Select-Object -Last 1).ToString().Trim()

            $incomingDump = Join-Path $configuration.BackupRoot "latest.dump.incoming"
            Copy-Item -LiteralPath $temporaryDump -Destination $incomingDump -Force
            if ((Get-FileHash -LiteralPath $incomingDump -Algorithm SHA256).Hash -ne $hash) {
                throw "Database backup copy verification failed. The previous backup and device lock were preserved."
            }

            $latestDump = Join-Path $configuration.BackupRoot "latest.dump"
            $latestManifest = Join-Path $configuration.BackupRoot "latest.json"
            $previousDump = Join-Path $configuration.BackupRoot "previous.dump"
            $previousManifest = Join-Path $configuration.BackupRoot "previous.json"
            if (Test-Path -LiteralPath $latestDump) {
                Copy-Item -LiteralPath $latestDump -Destination $previousDump -Force
            }
            if (Test-Path -LiteralPath $latestManifest) {
                Copy-Item -LiteralPath $latestManifest -Destination $previousManifest -Force
            }
            Move-Item -LiteralPath $incomingDump -Destination $latestDump -Force
            Save-JsonAtomic -Path $latestManifest -Value ([ordered]@{
                format = "postgresql-custom-dump"
                created_at_utc = [DateTime]::UtcNow.ToString("o")
                source_device = $device
                database = $configuration.DatabaseName
                alembic_version = $schemaVersion
                bytes = $size
                sha256 = $hash
                system_identifier = $changePosition.SystemIdentifier
                wal_lsn = $changePosition.WalLsn
            })
            Save-JsonAtomic -Path $autoStatePath -Value ([ordered]@{
                system_identifier = $changePosition.SystemIdentifier
                wal_lsn = $changePosition.WalLsn
                last_backup_sha256 = $hash
                updated_at_utc = [DateTime]::UtcNow.ToString("o")
            })

            $syncStatePath = Join-Path $configuration.RuntimeRoot "database-sync.json"
            Save-JsonAtomic -Path $syncStatePath -Value ([ordered]@{
                device = $device
                dirty = $true
                last_backup_sha256 = $hash
                session_id = $SessionId
                updated_at_utc = [DateTime]::UtcNow.ToString("o")
            })
            return [pscustomobject]@{
                Saved = $true
                Reason = "changed"
                Path = $latestDump
                Sha256 = $hash
            }
        } finally {
            if (Test-Path -LiteralPath $temporaryDump) {
                Remove-Item -LiteralPath $temporaryDump -Force
            }
        }
    } finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Reset-PostgresDatabase {
    param([Parameter(Mandatory = $true)]$Configuration)

    $terminateSql = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$($Configuration.DatabaseName)' AND pid <> pg_backend_pid();"
    Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
        "exec", "-T", "postgres", "psql",
        "-U", $Configuration.DatabaseUser,
        "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", $terminateSql
    ) | Out-Null
    Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
        "exec", "-T", "postgres", "dropdb",
        "-U", $Configuration.DatabaseUser, "--if-exists", $Configuration.DatabaseName
    ) | Out-Null
    Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
        "exec", "-T", "postgres", "createdb",
        "-U", $Configuration.DatabaseUser, $Configuration.DatabaseName
    ) | Out-Null
}

function Import-PostgresDump {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $containerDump = "/tmp/robotics-lab-restore-$([guid]::NewGuid().ToString('N')).dump"
    $preRestore = Join-Path $Configuration.RuntimeRoot "database-pre-restore.dump"
    Export-PostgresDump -Configuration $Configuration -Destination $preRestore
    try {
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "cp", $Source, "postgres:$containerDump"
        ) | Out-Null
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "exec", "-T", "postgres", "pg_restore", "--list", $containerDump
        ) | Out-Null
        Reset-PostgresDatabase -Configuration $Configuration
        Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
            "exec", "-T", "postgres", "pg_restore",
            "--exit-on-error", "--no-owner", "--no-privileges",
            "-U", $Configuration.DatabaseUser,
            "-d", $Configuration.DatabaseName,
            $containerDump
        ) | Out-Null
    } catch {
        $restoreError = $_
        Write-Warning "The synchronized backup could not be restored. Restoring the previous local database."
        Reset-PostgresDatabase -Configuration $Configuration
        $recoveryDump = "/tmp/robotics-lab-recovery-$([guid]::NewGuid().ToString('N')).dump"
        try {
            Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                "cp", $preRestore, "postgres:$recoveryDump"
            ) | Out-Null
            Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                "exec", "-T", "postgres", "pg_restore",
                "--exit-on-error", "--no-owner", "--no-privileges",
                "-U", $Configuration.DatabaseUser,
                "-d", $Configuration.DatabaseName,
                $recoveryDump
            ) | Out-Null
        } finally {
            try {
                Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                    "exec", "-T", "postgres", "rm", "-f", $recoveryDump
                ) | Out-Null
            } catch { }
        }
        throw "Synchronized database restore failed; the previous local database was recovered. $restoreError"
    } finally {
        try {
            Invoke-RoboticsCompose -Configuration $Configuration -Quiet -Arguments @(
                "exec", "-T", "postgres", "rm", "-f", $containerDump
            ) | Out-Null
        } catch { }
    }
}

function Start-RoboticsLocalPostgres {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [int]$DatabasePort = $script:DefaultDatabasePort,
        [string]$ProjectName = $script:DefaultProjectName,
        [string]$BackupRoot = "",
        [string]$RuntimeRoot = ""
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker Desktop is required for the local PostgreSQL database. Install or start Docker Desktop and try again."
    }
    & docker info --format "{{.ServerVersion}}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop is not running. Start Docker Desktop and try again."
    }

    $configuration = Get-LocalDatabaseConfiguration `
        -RepositoryRoot $RepositoryRoot `
        -DatabasePort $DatabasePort `
        -ProjectName $ProjectName `
        -BackupRoot $BackupRoot `
        -RuntimeRoot $RuntimeRoot
    New-Item -ItemType Directory -Force -Path $configuration.BackupRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $configuration.RuntimeRoot | Out-Null
    $lockPath = Join-Path $configuration.BackupRoot "active-device.json"
    $existingLock = Read-JsonFile -Path $lockPath
    $device = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { "unknown-windows-device" } else { $env:COMPUTERNAME }
    if ($existingLock -and $existingLock.device -ne $device) {
        throw "The database is assigned to '$($existingLock.device)' since $($existingLock.acquired_at_utc). Stop the app there and wait for the package to finish synchronizing before starting here."
    }

    $sessionId = [guid]::NewGuid().ToString("N")
    $createdNewLock = -not $existingLock
    Save-JsonAtomic -Path $lockPath -Value ([ordered]@{
        device = $device
        session_id = $sessionId
        acquired_at_utc = [DateTime]::UtcNow.ToString("o")
        repository = $configuration.RepositoryRoot
    })

    try {
        Invoke-RoboticsCompose -Configuration $configuration -Arguments @("up", "-d", "postgres") | Out-Null
        Wait-ForLocalPostgres -Configuration $configuration

        $manifestPath = Join-Path $configuration.BackupRoot "latest.json"
        $backupPath = Join-Path $configuration.BackupRoot "latest.dump"
        if ((Test-Path -LiteralPath $manifestPath) -xor (Test-Path -LiteralPath $backupPath)) {
            throw "The synchronized database backup is incomplete. Both latest.dump and latest.json are required."
        }

        $syncStatePath = Join-Path $configuration.RuntimeRoot "database-sync.json"
        $syncState = Read-JsonFile -Path $syncStatePath
        $latestHash = $null
        $restored = $false
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Read-JsonFile -Path $manifestPath
            $actualHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
            if ($actualHash -ne $manifest.sha256) {
                throw "The database backup checksum does not match its manifest. Wait for the package to finish synchronizing."
            }
            $latestHash = $actualHash
            $lastHash = if ($syncState) { $syncState.last_backup_sha256 } else { $null }
            $dirty = $syncState -and [bool]$syncState.dirty
            if ($dirty -and $lastHash -ne $latestHash) {
                throw "This computer has unexported database changes while the package contains a different backup. Do not overwrite either copy; resolve the handoff first."
            }
            $hasApplicationSchema = Test-LocalPostgresApplicationSchema -Configuration $configuration
            if ($lastHash -ne $latestHash -or -not $hasApplicationSchema) {
                Import-PostgresDump -Configuration $configuration -Source $backupPath
                $restored = $true
            }
        }

        Save-JsonAtomic -Path $syncStatePath -Value ([ordered]@{
            device = $device
            dirty = $true
            last_backup_sha256 = $latestHash
            session_id = $sessionId
            updated_at_utc = [DateTime]::UtcNow.ToString("o")
        })

        return [pscustomobject]@{
            SessionId = $sessionId
            ProjectName = $configuration.ProjectName
            DatabasePort = $configuration.DatabasePort
            DatabaseUrl = $configuration.DatabaseUrl
            BackupRoot = $configuration.BackupRoot
            RuntimeRoot = $configuration.RuntimeRoot
            RestoredBackup = $restored
            HasSynchronizedBackup = [bool]$latestHash
        }
    } catch {
        if ($createdNewLock -and (Test-Path -LiteralPath $lockPath)) {
            Remove-Item -LiteralPath $lockPath -Force
        }
        try {
            Invoke-RoboticsCompose -Configuration $configuration -Quiet -Arguments @("stop", "postgres") | Out-Null
        } catch { }
        throw
    }
}

function Complete-RoboticsLocalPostgres {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [int]$DatabasePort = $script:DefaultDatabasePort,
        [string]$ProjectName = $script:DefaultProjectName,
        [string]$BackupRoot = "",
        [string]$RuntimeRoot = ""
    )

    $configuration = Get-LocalDatabaseConfiguration `
        -RepositoryRoot $RepositoryRoot `
        -DatabasePort $DatabasePort `
        -ProjectName $ProjectName `
        -BackupRoot $BackupRoot `
        -RuntimeRoot $RuntimeRoot
    $backup = Save-RoboticsLocalPostgresBackup `
        -RepositoryRoot $configuration.RepositoryRoot `
        -SessionId $SessionId `
        -DatabasePort $configuration.DatabasePort `
        -ProjectName $configuration.ProjectName `
        -BackupRoot $configuration.BackupRoot `
        -RuntimeRoot $configuration.RuntimeRoot `
        -MutexTimeoutSeconds 60

    $syncStatePath = Join-Path $configuration.RuntimeRoot "database-sync.json"
    Save-JsonAtomic -Path $syncStatePath -Value ([ordered]@{
        device = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { "unknown-windows-device" } else { $env:COMPUTERNAME }
        dirty = $false
        last_backup_sha256 = $backup.Sha256
        session_id = $null
        updated_at_utc = [DateTime]::UtcNow.ToString("o")
    })
    $lockPath = Join-Path $configuration.BackupRoot "active-device.json"
    Remove-Item -LiteralPath $lockPath -Force
    Invoke-RoboticsCompose -Configuration $configuration -Quiet -Arguments @("stop", "postgres") | Out-Null
    Write-Output "Verified PostgreSQL backup saved to $($backup.Path)"
}

Export-ModuleMember -Function Start-RoboticsLocalPostgres, Save-RoboticsLocalPostgresBackup, Complete-RoboticsLocalPostgres
