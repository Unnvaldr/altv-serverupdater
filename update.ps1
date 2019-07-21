#
# Script Name: update.ps1
#
# Author: Lhoerion
#
# Description: The following script compares SHA-1 hashes of remote and local alt:V files. If local file is missing or outdated, script automatically downloads it to script directory.
#              Old files are preserved as *.old. Script also keep track of current branch and build. Server start script gets created if missing.
#
# Run Information: This script is run manually.
# Dependencies: >=PowerShell 5.0
#

Clear-Content -Path 'update.log' 2>&1 >$null
[System.Collections.ArrayList]$files=@()
function printAndLog($str, $type) {
    $date = Get-Date -UFormat '%T'
    if($type -eq 'ERR') {
        "[$date][Error] $str" | Add-Content -Path 'update.log' -NoNewline -PassThru | Write-Host -NoNewline -ForegroundColor 'Red'
    } elseif($type -eq 'WARN') {
        "[$date][Warning] $str" | Add-Content -Path 'update.log' -NoNewline -PassThru | Write-Host -NoNewline -ForegroundColor 'Yellow'
    } elseif($type -eq 'APP') {
        "$str" | Add-Content -Path 'update.log' -NoNewline -PassThru | Write-Host -NoNewline
    } else {
        "[$date] $str" | Add-Content -Path 'update.log' -NoNewline -PassThru | Write-Host -NoNewline
    }
}
function validateFiles() {
    $script:files.Clear();
    foreach($file in @('altv-server.exe','data/vehmodels.bin','data/vehmods.bin')) {
        if(!(Test-Path -Path "./$file") -or ((Get-FileHash -Path "./$file" -Algorithm 'SHA1').Hash.ToLower() -ne $updateData.hashList."$file")) {
            $script:files += $file;
        }
    }
    if(!(Test-Path -Path "./start.ps1")) {
        printAndLog "Server file ./start.ps1 not found, creating one . . . "
        $result=(New-Item -Path './start.ps1' -Value "./altv-server.exe`n" -Force)
        if($result) {
            printAndLog "done`n" 'APP'
        } else {
            printAndLog "failed`n" 'APP'
        }
    }
    if($localBuild -ne $remoteBuild) {
        printAndLog "Server files update is available`n"
    } elseif($files.Count -ne 0) {
        printAndLog "Server files are invalidated/corrupted, $($script:files.Count) in total`n"
    } else {
        printAndLog "Server files are up-to-date, no action required`n"
    }

    $localBuild=$remoteBuild
    [ordered]@{branch=$localBranch;build=$localBuild} | ConvertTo-Json > './update.cfg'
}
function downloadFiles() {
    if($script:files.Count -eq 0) {
        return
    }
    foreach($file in $script:files) {
        $parentDir=(Split-Path -Path "$file" -Parent)
        printAndLog "Downloading file ./$file  . . . "
        if(Test-Path -Path "./$file") {
            Move-Item -Path "./$file" -Destination "./$file.old" -Force >$null
        }
        if(!(Test-Path -Path "./$parentDir")) {
            New-Item -Path "./$parentDir" -ItemType 'Directory' -Force >$null
        }
        $progressPreference = 'silentlyContinue'
        $result=(Invoke-WebRequest -Uri "https://cdn.altv.mp/server/$localBranch/x64_win32/$file" -UseBasicParsing -OutFile "./$file" -PassThru)
        if($result.StatusCode -eq 200) {
            printAndLog "done`n" 'APP'
        } else {
            printAndLog "failed`n" 'APP'
        }
        $progressPreference = 'Continue'
    }
    validateFiles
}
if(!(Test-Path './update.cfg')) {
    New-Item './update.cfg'  -Force >$null
    [ordered]@{branch='stable'} | ConvertTo-Json > './update.cfg'
}
$updateCfg=$(Get-Content './update.cfg' | ConvertFrom-Json)
$localBranch=$updateCfg.branch
if(!$localBranch -or $localBranch -ne 'stable' -and $localBranch -ne 'beta' -and $localBranch -ne 'alpha') { $localBranch='stable' }
try {
    $updateData=(Invoke-RestMethod -Uri "https://cdn.altv.mp/server/$localBranch/x64_win32/update.json")
} catch {
    printAndLog "Failed to check for update, try again later`n" 'ERR'
    exit
}
$remoteBuild=$updateData.latestBuildNumber
$localBuild=$updateCfg.build
if(!($localBuild -match '^[0-9]+$')) { $localBuild=$remoteBuild }
validateFiles
downloadFiles
