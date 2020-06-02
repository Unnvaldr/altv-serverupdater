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

Param([Alias("no-logfile")][Switch]$noLogFile, [Alias("no-backup")][Switch]$noBackup)
[System.Collections.ArrayList]$files=@()
function printAndLog($str, $type) {
	$date=(Get-Date -UFormat '%T')
	if($type -eq 'ERR') {
		"[$date][Error] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | Write-Host -NoNewline -ForegroundColor 'Red'
	} elseif($type -eq 'WARN') {
		"[$date][Warning] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | Write-Host -NoNewline -ForegroundColor 'Yellow'
	} elseif($type -eq 'APP') {
		"$str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | Write-Host -NoNewline
	} else {
		"[$date] $str" | %{if($noLogFile){$_}else{$_|Add-Content -Path 'update.log' -NoNewline -PassThru}} | Write-Host -NoNewline
	}
}
function fetchUpdateData() {
	$hashTable=@{}
	try {
		$script:updateData=(Invoke-RestMethod -Uri "https://cdn.altv.mp/server/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
		$script:updateData.hashList.psobject.properties | Foreach { $hashTable[$_.Name]=@($_.Value,'server') }
	} catch {
		printAndLog "Failed to check for update, try again later`n" 'ERR'
		exit
	}
	try {
		$moduleName = if($script:updateData.latestBuildNumber -ge 1232) { 'js-module' } else { 'node-module' }
		$updateData2=(Invoke-RestMethod -Uri "https://cdn.altv.mp/$moduleName/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
		$updateData2.hashList.psobject.properties | Foreach { $hashTable[$_.Name]=@($_.Value,"$moduleName") }
	} catch {
		printAndLog "Failed to check for node-module update`n" 'WARN'
	}
	try {
		$updateData3=(Invoke-RestMethod -Uri "https://cdn.altv.mp/coreclr-module/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
		$updateData3.hashList.psobject.properties | Foreach { $hashTable[$_.Name]=@($_.Value,'coreclr-module') }
		$hashTable['modules/csharp-module.dll'] = @('1010101010101010101010101010101010101010','coreclr-module')
	} catch {
		printAndLog "Failed to check for csharp-module update`n" 'WARN'
	}
	$script:updateData.hashList=[pscustomobject]$hashTable
}
function validateFiles() {
	$script:files.Clear()
	$hashList=$script:updateData.hashList
	foreach($file in ($hashList | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name)) {
		if(!(Test-Path -Path "$file") -or ((Get-FileHash -Path "$file" -Algorithm 'SHA1').Hash.ToLower() -ne $hashList."$file"[0])) {
			$script:files+=$file
		}
	}
	if($script:files.Contains('modules/csharp-module.dll') -and (Test-Path -Path 'modules/csharp-module.dll') -and !$script:files.Contains('AltV.Net.Host.dll')) {
		$script:files.Remove('modules/csharp-module.dll')
	}
	if(!(Test-Path -Path "start.ps1")) {
		printAndLog "Server file start.ps1 not found, creating one . . . "
		$result=(New-Item -Path 'start.ps1' -Value "`$Host.UI.RawUI.BackgroundColor='black'`n`$Host.UI.RawUI.ForegroundColor='gray'`n.\altv-server.exe `$args`n" -Force)
		if($result) {
			printAndLog "done`n" 'APP'
		} else {
			printAndLog "failed`n" 'APP'
		}
	}
	if($script:updateData.latestBuildNumber -ge 1232) {
		$nodeExist = Test-Path -Path "libnode.dll"
		$moduleExist = Test-Path -Path "modules/node-module.dll"
		if($nodeExist -or $moduleExist) {
			printAndLog "Found old node-module files, removing . . .`n"
			if($nodeExist) {
				Remove-Item -Path "libnode.dll" -Force >$null
			}
			if($moduleExist) {
				Remove-Item -Path "modules/node-module.dll" -Force >$null
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

	$localBuild=$remoteBuild
	[ordered]@{branch=$localBranch;build=$localBuild} | ConvertTo-Json > 'update.cfg'
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
		$progressPreference='Continue'
	}
	validateFiles
}

if(!$noLogFile) {
	Clear-Content -Path 'update.log' 2>&1 >$null
}
if(!(Test-Path 'update.cfg')) {
	New-Item 'update.cfg'  -Force >$null
	[ordered]@{branch='release'} | ConvertTo-Json > 'update.cfg'
}
$updateCfg=$(Get-Content 'update.cfg' | ConvertFrom-Json)
$localBranch=$updateCfg.branch
if(!$localBranch -or $localBranch -ne 'release' -and $localBranch -ne 'rc' -and $localBranch -ne 'dev') { $localBranch='release' }
fetchUpdateData
$remoteBuild=$updateData.latestBuildNumber
$localBuild=$updateCfg.build
if(!($localBuild -match '^[0-9]+$')) { $localBuild=$remoteBuild }
validateFiles
downloadFiles
