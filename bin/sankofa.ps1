# This is the windows equivalent of the `third_party/flutter/bin/internal/shared.sh` script
# compiles `sankofa_cli/bin/sankofa_cli.dart` to `bin/cache/sankofa.snapshot`

$ErrorActionPreference = "Stop"

# We are running from $sankofaRootDir\bin
$sankofaBinDir = (Get-Item $PSScriptRoot).FullName
$sankofaRootDir = (Get-Item $sankofaBinDir\..\).FullName
$flutterVersion = Get-Content "$sankofaBinDir\internal\flutter.version"
$sankofaCacheDir = [IO.Path]::Combine($sankofaRootDir, "bin", "cache")
$sankofaCliDir = [IO.Path]::Combine($sankofaRootDir, "packages", "sankofa_cli")
$snapshotPath = [IO.Path]::Combine($sankofaCacheDir, "sankofa.snapshot")
$stampPath = [IO.Path]::Combine($sankofaCacheDir, "sankofa.stamp")
$flutterPath = [IO.Path]::Combine($sankofaCacheDir, "flutter", $flutterVersion)
$flutter = [IO.Path]::Combine($sankofaCacheDir, "flutter", $flutterVersion, "bin", "flutter.bat")
$sankofaScript = [IO.Path]::Combine($sankofaCliDir, "bin", "sankofa.dart")
$dart = [IO.Path]::Combine($flutterPath, "bin", "cache", "dart-sdk", "bin", "dart.exe")

# Executes $command and redirects as much output to $null as possible.
#
# This is a workaround for old versions of Powershell treating any write to
# the Error stream with $ErrorActionPreference = "Stop" as a terminating error.
# This is fixed in Powershell 7.1.
# 
# See https://github.com/PowerShell/PowerShell/issues/4002 for more info.
function Invoke-SilentlyIfNeeded($command) {
    $psVersion = $PSVersionTable.PSVersion
    $isErrorStreamIssueFixed = $psVersion.Major -ge 7 -and $psVersion.Minor -ge 1
    if ($isErrorStreamIssueFixed) {
        # Execute the command with no redirection.
        & $command
    }
    else {
        # Otherwise redirect everything _but_ the Error stream to $null. See
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-7.3#long-description
        # for a description of these streams.
        & $command  1> $null 3> $null 4> $null 5> $null 6> $null
    }
}

function Test-GitConfigLongpaths {
    $longpathsEnabled = git config --system core.longpaths
    if ($longpathsEnabled -ne "true") {
        Write-Output "Git is not configured to allow long paths. This can cause issues with Sankofa's Flutter checkout. Please run 'git config --system core.longpaths true' to enable long paths."
    }
}

function Test-GitInstalled {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Debug "Git is installed."
    }
    else {
        Write-Output "No git installation detected. Git is required to use sankofa."
        exit 1
    }
}

function Test-SankofaNeedsUpdate {
    Write-Debug "Checking whether sankofa needs to be rebuilt"

    # Invalidate cache if:
    #  * snapshotFile is not a file, or
    #  * stampFile is not a file, or
    #  * stampFile is an empty file, or
    #  * Contents of stampFile contains a different git hash than HEAD, or
    #  * pubspec.yaml last modified after pubspec.lock
    $snapshotFile = [System.IO.FileInfo] $snapshotPath
    $stampFile = [System.IO.FileInfo] $stampPath
    $pubspecFile = [System.IO.FileInfo] "$sankofaCliDir\pubspec.yaml"
    $pubspecLockFile = [System.IO.FileInfo] "$sankofaRootDir\pubspec.lock"

    Push-Location $sankofaRootDir
    $compileKey = & { git rev-parse HEAD } -split
    Pop-Location

    if (!$snapshotFile.Exists) {
        Write-Debug "snapshot file does not exist, sankofa needs update"
        return $true
    }

    if (!$stampFile.Exists) {
        Write-Debug "stamp file does not exist at $($stampFile), sankofa needs update"
        return $true
    }

    if ($stampFile.Length -eq 0) {
        Write-Debug "stamp file is empty, sankofa needs update"
        return $true
    }

    $stampFileContents = Get-Content $stampFile
    if ($stampFileContents -ne $compileKey) {
        Write-Debug "contents of stamp file do not match compile key ($($stampFileContents) vs $($compileKey)), sankofa needs update"
        return $true
    }

    if ($pubspecFile.LastWriteTime -gt $pubspecLockFile.LastWriteTime) {
        Write-Debug "pubspec.yaml updated more recently than pubspec.lock, sankofa needs update"
        return $true
    }

    Write-Debug "sankofa does not need update"
    return $false
}

function Update-Flutter {
    Write-Output "Updating Flutter..."

    if (!(Test-Path $flutterPath)) {
        Invoke-SilentlyIfNeeded {
            git clone --filter=tree:0 https://github.com/sankofatech/flutter.git --no-checkout "$flutterPath" 
        }
    }
    else {
        Invoke-SilentlyIfNeeded {
            git -C "$flutterPath" fetch
        }
    }

    Invoke-SilentlyIfNeeded {
        # -c to avoid printing a warning about being in a detached head state.
        git -C "$flutterPath" -c advice.detachedHead=false checkout "$flutterVersion"
    }

    # Set FLUTTER_STORAGE_BASE_URL=https://download.sankofa.dev and execute
    # a `flutter` command to trigger a download of Dart, etc.
    $env:FLUTTER_STORAGE_BASE_URL = 'https://download.sankofa.dev';
    & $flutter --version
    Remove-Item Env:\FLUTTER_STORAGE_BASE_URL
}

function Update-Sankofa {
    Push-Location $sankofaRootDir
    $compileKey = & { git rev-parse HEAD } -split
    Pop-Location
 
    Write-Output "Rebuilding sankofa..."

    Update-Flutter

    Push-Location $sankofaCliDir
    & $dart pub get
    Pop-Location
    # pub get may not update pubspec.lock's mtime if dependencies are unchanged,
    # which would cause the pubspec.yaml -gt pubspec.lock check to keep
    # triggering a rebuild on every invocation.
    (Get-Item "$sankofaRootDir/pubspec.lock").LastWriteTime = Get-Date

    Write-Output "Compiling sankofa..."

    # Compile our snapshot
    # We invoke `$SNAPSHOT_PATH completion` to trigger the "completion" command, which
    # avoids executing as much of our code as possible. We do this because running
    # the script here (instead of from the compiled snapshot) invalidates a lot of
    # assumptions we make about the cwd in the sankofa_cli tool.
    & $dart --verbosity=error --disable-dart-dev --snapshot="$snapshotPath" `
        --snapshot-kind="app-jit" --packages="$sankofaRootDir/.dart_tool/package_config.json" `
        --no-enable-mirrors "$sankofaScript" completion > $null

    Write-Debug "writing $compileKey to $stampPath"
    Set-Content -Path $stampPath -Value $compileKey
}

Test-GitInstalled

Test-GitConfigLongpaths

if (Test-SankofaNeedsUpdate) {
    Update-Sankofa
}

& $dart --disable-dart-dev --packages="$sankofaRootDir\.dart_tool\package_config.json" "$snapshotPath" $args
