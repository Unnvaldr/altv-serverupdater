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
Param([Switch]$noBackup)
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
	foreach($file in ($updateData.hashList | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name)) {
		if(!(Test-Path -Path "$file") -or ((Get-FileHash -Path "$file" -Algorithm 'SHA1').Hash.ToLower() -ne $updateData.hashList."$file"[0])) {
			$script:files += $file;
		}
	}
	if(!(Test-Path -Path "start.ps1")) {
		printAndLog "Server file start.ps1 not found, creating one . . . "
		$result=(New-Item -Path 'start.ps1' -Value ".\altv-server.exe`n" -Force)
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
		$fileName=(Split-Path -Path "$file" -Leaf)
		if($dlType -ne 'server' -and $dlType -ne 'node-module') { $file=$fileName }
		printAndLog "Downloading file $outDir\$fileName . . . "
		if(!$noBackup -and (Test-Path -Path "$file")) {
			Move-Item -Path "$file" -Destination "$file.old" -Force >$null
		}
		if(!(Test-Path -Path "$outDir")) {
			New-Item -Path "$outDir" -ItemType 'Directory' -Force >$null
		}
		$progressPreference = 'silentlyContinue'
		$result=(Invoke-WebRequest -Uri "https://cdn.altv.mp/$dlType/$localBranch/x64_win32/$file" -UserAgent 'AltPublicAgent' -UseBasicParsing  -OutFile "$outDir\$fileName" -PassThru)
		if($result.StatusCode -eq 200) {
			printAndLog "done`n" 'APP'
		} else {
			printAndLog "failed`n" 'APP'
		}
		$progressPreference = 'Continue'
	}
	validateFiles
}
if(!(Test-Path 'update.cfg')) {
	New-Item 'update.cfg'  -Force >$null
	[ordered]@{branch='stable'} | ConvertTo-Json > 'update.cfg'
}
$updateCfg=$(Get-Content 'update.cfg' | ConvertFrom-Json)
$localBranch=$updateCfg.branch
if(!$localBranch -or $localBranch -ne 'stable' -and $localBranch -ne 'beta' -and $localBranch -ne 'alpha') { $localBranch='stable' }
try {
	$updateData=(Invoke-RestMethod -Uri "https://cdn.altv.mp/server/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
	$hashTable = @{}
	$updateData.hashList.psobject.properties | Foreach { $hashTable[$_.Name] = @($_.Value,'server') }
	if($localBranch -ne 'stable') {
		$updateData2=(Invoke-RestMethod -Uri "https://cdn.altv.mp/node-module/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
		$updateData3=(Invoke-RestMethod -Uri "https://cdn.altv.mp/coreclr-module/$localBranch/x64_win32/update.json" -UserAgent 'AltPublicAgent')
		$updateData2.hashList.psobject.properties | Foreach { $hashTable[$_.Name] = @($_.Value,'node-module') }
		$updateData3.hashList.psobject.properties | Foreach { $hashTable["modules/$($_.Name)"] = @($_.Value,'coreclr-module') }
	} else {
		printAndLog "Checking for update of csharp-module and node-module is not possible yet in stable branch`n" 'WARN'
	}
	$updateData.hashList = [pscustomobject]$hashTable;
} catch {
	printAndLog "Failed to check for update, try again later`n" 'ERR'
	exit
}
$remoteBuild=$updateData.latestBuildNumber
$localBuild=$updateCfg.build
if(!($localBuild -match '^[0-9]+$')) { $localBuild=$remoteBuild }
validateFiles
downloadFiles
