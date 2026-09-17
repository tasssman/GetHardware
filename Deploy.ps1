[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Destination = '\\ntshare\helpdesk\scripts\GetHardware',
    [System.Management.Automation.PSCredential]$Credential
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$DatabaseName = 'hardware-models.json'
$PublishFiles = @(
    'Get-HardwareInventory.ps1',
    'README.md',
    'CHANGELOG.md'
)

function Test-ModelDatabase {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $ParsedModels = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        $Models = @($ParsedModels | ForEach-Object { $_ })
    }
    catch {
        throw "Baza modeli '$Path' nie jest poprawnym plikiem JSON: $($_.Exception.Message)"
    }

    if ($Models.Count -eq 0) {
        throw "Baza modeli '$Path' jest pusta."
    }

    $RequiredProperties = @(
        'model',
        'baseboardFallback',
        'memorySpec',
        'powerMaxW',
        'powerW',
        'other',
        'deviceType'
    )

    foreach ($Model in $Models) {
        foreach ($Property in $RequiredProperties) {
            if ($Model.PSObject.Properties.Name -notcontains $Property) {
                throw "Wpis w bazie '$Path' nie zawiera pola '$Property'."
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Model.model)) {
            throw "Baza modeli '$Path' zawiera wpis z pustą nazwą modelu."
        }
        if ([string]::IsNullOrWhiteSpace([string]$Model.baseboardFallback)) {
            throw "Model '$($Model.model)' ma puste pole baseboardFallback."
        }

        $PowerMax = 0
        $Power = 0
        if (-not [int]::TryParse([string]$Model.powerMaxW, [ref]$PowerMax) -or $PowerMax -lt 0) {
            throw "Model '$($Model.model)' ma nieprawidłowe powerMaxW."
        }
        if (-not [int]::TryParse([string]$Model.powerW, [ref]$Power) -or $Power -lt 0) {
            throw "Model '$($Model.model)' ma nieprawidłowe powerW."
        }
    }

    $Duplicate = $Models |
        Group-Object { ([string]$_.model).Trim().ToUpperInvariant() } |
        Where-Object Count -gt 1 |
        Select-Object -First 1
    if ($null -ne $Duplicate) {
        throw "Baza modeli '$Path' zawiera zduplikowany model '$($Duplicate.Group[0].model)'."
    }
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target
    )

    $TargetDirectory = Split-Path -Parent $Target
    $TemporaryTarget = Join-Path $TargetDirectory (
        ".$([IO.Path]::GetFileName($Target)).$([guid]::NewGuid().ToString('N')).deploying"
    )

    try {
        Copy-Item -LiteralPath $Source -Destination $TemporaryTarget -Force
        $SourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $TemporaryHash = (Get-FileHash -LiteralPath $TemporaryTarget -Algorithm SHA256).Hash
        if ($SourceHash -ne $TemporaryHash) {
            throw "Weryfikacja kopii pliku '$Source' nie powiodła się."
        }

        Move-Item -LiteralPath $TemporaryTarget -Destination $Target -Force
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryTarget -PathType Leaf) {
            Remove-Item -LiteralPath $TemporaryTarget -Force -ErrorAction SilentlyContinue
        }
    }
}

$DriveName = $null
$DeploymentRoot = $Destination

try {
    if ($null -ne $Credential) {
        $DriveName = 'GHD' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-PSDrive `
            -Name $DriveName `
            -PSProvider FileSystem `
            -Root $Destination `
            -Credential $Credential `
            -Scope Script `
            -ErrorAction Stop | Out-Null
        $DeploymentRoot = $DriveName + ':\'
    }

    if (-not (Test-Path -LiteralPath $DeploymentRoot -PathType Container)) {
        throw "Katalog docelowy '$Destination' nie istnieje. Skrypt nie utworzy go automatycznie."
    }

    $SourceRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $ResolvedDeploymentRoot = (Resolve-Path -LiteralPath $DeploymentRoot).ProviderPath.TrimEnd('\')
    if ($SourceRoot -ieq $ResolvedDeploymentRoot) {
        throw 'Katalog źródłowy i docelowy nie mogą być tym samym katalogiem.'
    }

    foreach ($RelativePath in $PublishFiles) {
        $SourcePath = Join-Path $SourceRoot $RelativePath
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
            throw "Brakuje pliku przeznaczonego do publikacji: '$SourcePath'."
        }
    }

    # Produkcyjna baza jest źródłem prawdy, ponieważ uruchomienia na laptopach
    # dopisują do niej nowe modele. Nigdy nie publikujemy lokalnej kopii bazy.
    $RemoteDatabasePath = Join-Path $DeploymentRoot $DatabaseName
    if (-not (Test-Path -LiteralPath $RemoteDatabasePath -PathType Leaf)) {
        throw "Na serwerze nie znaleziono bazy '$RemoteDatabasePath'. Publikacja została przerwana."
    }

    $LocalDatabasePath = Join-Path $SourceRoot $DatabaseName
    $TemporaryDatabasePath = Join-Path $SourceRoot (
        ".$DatabaseName.$([guid]::NewGuid().ToString('N')).downloading"
    )

    try {
        Copy-Item `
            -LiteralPath $RemoteDatabasePath `
            -Destination $TemporaryDatabasePath `
            -Force `
            -WhatIf:$false
        Test-ModelDatabase -Path $TemporaryDatabasePath

        $DatabaseChanged = -not (Test-Path -LiteralPath $LocalDatabasePath -PathType Leaf)
        if (-not $DatabaseChanged) {
            $LocalHash = (Get-FileHash -LiteralPath $LocalDatabasePath -Algorithm SHA256).Hash
            $RemoteHash = (Get-FileHash -LiteralPath $TemporaryDatabasePath -Algorithm SHA256).Hash
            $DatabaseChanged = $LocalHash -ne $RemoteHash
        }

        if ($DatabaseChanged -and $PSCmdlet.ShouldProcess(
                $LocalDatabasePath,
                "pobrać i zapisać produkcyjną bazę z '$Destination'"
            )) {
            if (Test-Path -LiteralPath $LocalDatabasePath -PathType Leaf) {
                $BackupRoot = Join-Path $SourceRoot '.deploy-backup'
                if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
                    New-Item -ItemType Directory -Path $BackupRoot | Out-Null
                }
                $BackupName = 'hardware-models.{0}.{1}.json' -f `
                    (Get-Date -Format 'yyyyMMdd-HHmmss'),
                    ([guid]::NewGuid().ToString('N').Substring(0, 8))
                Copy-Item `
                    -LiteralPath $LocalDatabasePath `
                    -Destination (Join-Path $BackupRoot $BackupName)
            }

            Copy-FileAtomically -Source $TemporaryDatabasePath -Target $LocalDatabasePath
            Write-Host 'Pobrano i zweryfikowano produkcyjną bazę modeli.' -ForegroundColor Green
        }
        elseif (-not $DatabaseChanged) {
            Write-Host 'Lokalna baza modeli jest zgodna z bazą produkcyjną.' -ForegroundColor DarkGreen
        }
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryDatabasePath -PathType Leaf) {
            Remove-Item `
                -LiteralPath $TemporaryDatabasePath `
                -Force `
                -ErrorAction SilentlyContinue `
                -WhatIf:$false
        }
    }

    foreach ($RelativePath in $PublishFiles) {
        $SourcePath = Join-Path $SourceRoot $RelativePath
        $TargetPath = Join-Path $DeploymentRoot $RelativePath

        if ($PSCmdlet.ShouldProcess($TargetPath, "opublikować '$RelativePath'")) {
            Copy-FileAtomically -Source $SourcePath -Target $TargetPath
            Write-Host "Opublikowano: $RelativePath" -ForegroundColor Green
        }
    }

    if ($WhatIfPreference) {
        Write-Host "Sprawdzono plan publikacji do '$Destination'. Nie zapisano żadnych zmian." -ForegroundColor Cyan
    }
    else {
        Write-Host "Publikacja do '$Destination' zakończona. Baza na serwerze nie została zmieniona." -ForegroundColor Cyan
    }
}
finally {
    if ($null -ne $DriveName) {
        Remove-PSDrive `
            -Name $DriveName `
            -Scope Script `
            -Force `
            -ErrorAction SilentlyContinue `
            -WhatIf:$false
    }
}
