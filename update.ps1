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

Param([Alias("no-logfile")][Switch]$noLogFile, [Alias("no-backup")][Switch]$noBackup, [Alias("dry-run")][Switch]$dryRun, [Switch]$silent)
[System.Collections.ArrayList]$files=@()
function printAndLog($str, $type) {
  $date=(Get-Date -UFormat '%T')
  if($type -eq 'ERR') {
    "[$date][Error] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | %{if(-not $silent) { $_ | Write-Host -NoNewline } else { $_ > $null }}
  } elseif($type -eq 'WARN') {
    "[$date][Warning] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | %{if(-not $silent) { $_ | Write-Host -NoNewline } else { $_ > $null }}
  } elseif($type -eq 'APP') {
    "$str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | %{if(-not $silent) { $_ | Write-Host -NoNewline } else { $_ > $null }}
  } else {
    "[$date] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | %{if(-not $silent) { $_ | Write-Host -NoNewline } else { $_ > $null }}
  }
}
function semVerCmp($verA, $verB) {
  Set-Variable "semVerRegex" -Option "Constant" -Value $([System.Text.RegularExpressions.Regex]"^(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$")
  $matchA = $semVerRegex.Match($verA.TrimStart('v'));
  $matchB = $semVerRegex.Match($verB.TrimStart('v'));
  if($verA -eq $verB) { return 0 }
  if((-not $matchA.Groups[4].Success) -and $matchB.Groups[4].Success) {
    return 1
  } elseif($matchA.Groups[4].Success -and (-not $matchB.Groups[4].Success)) {
    return -1
  }
  for($i=1; $i -lt $matchA.Groups.Count; $i++) {
    $a=$matchA.Groups[$i]
    $b=$matchB.Groups[$i]
    if(($i -eq 2) -and ((-not $a.Success) -or (-not $b.Success))) { continue }
    if($a.Value -gt $b.Value) {
      return 1
    } elseif($a.Value -lt $b.Value) {
      return -1
    }
  }
  return 0
}
function getFileHash($file) {
  return (Get-FileHash -Path "$file" -Algorithm 'SHA1').Hash
}
function fetchUpdateData() {
  $hashTable=@{}
  try {
    $script:updateData=(Invoke-RestMethod -Uri "https://cdn.altv.mp/server/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
    $script:updateData.hashList.psobject.properties | Foreach { $hashTable[$_.Name]=@($_.Value,'server') }
    if(!$hashTable.Contains('data/clothes.bin')) {
      $hashTable['data/clothes.bin']=@('0'.PadRight(39, '0'), 'server')
    }
  } catch {
    printAndLog "Failed to check for update, try again later`n" 'ERR'
    exit 1
  }
  foreach($moduleName in $modules) {
    try {
      if($moduleName -eq 'csharp-module') { $moduleName='coreclr-module' }
      $updateData2=(Invoke-RestMethod -Uri "https://cdn.altv.mp/$moduleName/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
      $updateData2.hashList.psobject.properties | Foreach { $hashTable[$_.Name]=@($_.Value,"$moduleName") }
    } catch {
      printAndLog "Failed to check for $moduleName update`n" 'WARN'
    }
  }
  $script:updateData.hashList=[pscustomobject]$hashTable
}
function validateFiles() {
  $script:files.Clear()
  $hashList=$script:updateData.hashList
  foreach($file in ($hashList | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name)) {
    if(-not (Test-Path -Path "$file") -or ('0'.PadRight(39, '0') -ne $hashList."$file"[0] -and (getFileHash "$file") -ne $hashList."$file"[0])) {
      $script:files+=$file
    }
  }
  if(!(Test-Path -Path "server.cfg")) {
    printAndLog "Server file server.cfg not found, creating one . . . "
    if(-not $dryRun) {
      $result=(New-Item -Path 'server.cfg' -Value "name: 'alt:V Server'`nhost: 0.0.0.0`nport: 7788`nplayers: 128`n#password: ultra-password`nannounce: false`n#token: YOUR_TOKEN`ngamemode: Freeroam`nwebsite: example.com`nlanguage: en`ndescription: 'alt:V Sample Server'`nmodules: [`n  `n]`nresources: [`n  `n]`n" -Force)
      if($result) {
        printAndLog "done`n" 'APP'
      } else {
        printAndLog "failed`n" 'APP'
      }
    } else {
      printAndLog "done`n" 'APP'
    }
  }
  if(($script:updateData.latestBuildNumber -is [string]) -or ($script:updateData.latestBuildNumber -ge 1232)) {
    $nodeExist = Test-Path -Path "libnode.dll"
    $moduleExist = Test-Path -Path "modules/node-module.dll"
    if($nodeExist -or $moduleExist) {
      printAndLog "Found old node-module files, removing . . . "
      if(-not $dryRun) {
        if($nodeExist) {
          $result1=Remove-Item -Path "libnode.dll" -Force >$null
        }
        if($moduleExist) {
          $result2=Remove-Item -Path "modules/node-module.dll" -Force >$null
        }
        if($result1 -and $result2) {
          printAndLog "done`n" 'APP'
        } else {
          printAndLog "failed`n" 'APP'
        }
      } else {
        printAndLog "done`n" 'APP'
      }
    }
  }
  if($localBuild -ne $remoteBuild) {
    printAndLog "Server files update is available`n"
  } elseif($files.Count -ne 0) {
    printAndLog "Server files are invalidated/corrupted, $($script:files.Count) in total`n"
  } else {
    printAndLog "Server files are up-to-date, no action required`n"
  }

  if(!$dryRun) {
    $localBuild=$remoteBuild
    [ordered]@{branch=$localBranch;build=$localBuild;modules=$modules} | ConvertTo-Json | Out-File -FilePath 'update.cfg' -Encoding 'default'
  }
}
function downloadFiles() {
  if($script:files.Count -eq 0) {
    return
  }
  foreach($file in $script:files) {
    $dlType=($updateData.hashList."$file"[1])
    $outDir=(Split-Path -Path "$file" -Parent).Replace('/', '\')
    if($outDir -eq '') { $outDir='.' }
    printAndLog "Downloading file $file . . . "
    if(-not $dryRun) {
      if(!$noBackup -and (Test-Path -Path "$file")) {
        Move-Item -Path "$file" -Destination "$file.old" -Force >$null
      }
      if(!(Test-Path -Path "$outDir")) {
        New-Item -Path "$outDir" -ItemType 'Directory' -Force >$null
      }
      $progressPreference='silentlyContinue'
      $result=(Invoke-WebRequest -Uri "https://cdn.altv.mp/$dlType/$localBranch/x64_win32/${file}?build=$localBuild" -UserAgent 'AltPublicAgent' -UseBasicParsing -OutFile "$file" -PassThru)
      if($result.StatusCode -eq 200) {
        printAndLog "done`n" 'APP'
      } else {
        printAndLog "failed`n" 'APP'
      }
    } else {
      printAndLog "done`n" 'APP'
    }
    $progressPreference='Continue'
  }
  validateFiles
}

if(!$noLogFile) {
  Clear-Content -Path 'update.log' 2>&1 >$null
}
if((-not $dryRun) -and !(Test-Path 'update.cfg')) {
  New-Item 'update.cfg' -Force >$null
  [ordered]@{branch='release';modules=@('js-module')} | ConvertTo-Json | Out-File -FilePath 'update.cfg' -Encoding 'default'
}
$updateCfg=if(Test-Path 'update.cfg') { $(Get-Content 'update.cfg' | ConvertFrom-Json) } else { '{}' | ConvertFrom-Json }
$localBranch=$updateCfg.branch
if(((-not $localBranch) -or ($localBranch -ne 'release')) -and ($localBranch -ne 'rc') -and ($localBranch -ne 'dev')) { $localBranch='release' }
$modules=$updateCfg.modules
if(-not $modules) { $modules=@('js-module') }
fetchUpdateData
$remoteBuild=$updateData.latestBuildNumber
if($updateData.latestBuildNumber -eq -1) { $remoteBuild=$updateData.version }
$localBuild=$updateCfg.build
if((-not $localBuild) -or ($localBuild -eq -1)) { $localBuild=$remoteBuild }
printAndLog "Current version: $localBuild`n"
printAndLog "Latest version: $remoteBuild`n"
validateFiles
downloadFiles
