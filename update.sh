#!/bin/bash
#
# Script Name: update.sh
#
# Author: Lhoerion
#
# Description: The following script compares SHA-1 hashes of remote and local alt:V files. If local file is missing or outdated, script automatically downloads it to script directory.
#              Old files are preserved as *.old. Script also keep track of current branch and build. Server start script gets created if missing.
#
# Run Information: This script is run manually.
# Dependencies: coreutils, wget, >=jq_1.4
#

noBackup=false
noLogFile=false
for arg in "$@"
do
	if [ $arg = '--no-logfile' ]; then
		noLogFile=true
	elif [ $arg = '--no-backup' ]; then
		noBackup=true
	fi
done
files=()
printAndLog() {
	if [ "$2" = 'ERR' ]; then
		printf "\e[91m[$(date +%T)][Error] $1\e[39m" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
	elif [ "$2" = 'WARN' ]; then
		printf "\e[93m[$(date +%T)][Warning] $1\e[39m" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
	elif [ "$2" = 'APP' ]; then
		printf "$1" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
	else
		printf "[$(date +%T)] $1" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
	fi
}
fetchUpdateData() {
	updateData=$(curl -s "https://cdn.altv.mp/server/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData | jq -e '.' >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for update, try again later\n" 'ERR'
		exit
	fi
	str='. | to_entries | map(if .key=="hashList" then {"key":.key} + {"value":(.value | to_entries | map(. + {"value":[.value, "%s"]}) | from_entries)} else . end) | from_entries'
	updateTmp=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp 
	updateTmp2=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp2
	updateTmp3=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp3
	echo $updateData | jq -c "$(printf "$str" 'server')" > $updateTmp
	updateData2=$(curl -s "https://cdn.altv.mp/node-module/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData2 | jq -e '.' >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for node-module update\n" 'WARN'
	else
		echo $updateData2 | jq -c "$(printf "$str" 'node-module')" > $updateTmp2
		unset updateData2
	fi
	updateData3=$(curl -s "https://cdn.altv.mp/coreclr-module/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData3 | jq -e '.' >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for csharp-module update\n" 'WARN'
	else
		updateData3=$(echo $updateData3 | jq '.hashList |=  . + {"modules/libcsharp-module.so":"1010101010101010101010101010101010101010"}')
		echo $updateData3 | jq -c "$(printf "$str" 'coreclr-module')" > $updateTmp3
		unset updateData3
	fi
	updateData=$(jq -s '.[0].latestBuildNumber as $b | reduce .[] as $x ({}; . * $x) | .latestBuildNumber=$b' $updateTmp $updateTmp2 $updateTmp3)
	rm $updateTmp
	rm $updateTmp2
	rm $updateTmp3
}
validateFiles() {
	files=()
	for file in $(echo $updateData | jq -r '.hashList | keys[]')
	do
		if [[ ! -e "$file" || $(sha1sum "$file" | awk '{print $1}') != "$(echo "${updateData}" | jq -r ".hashList.\"$file\"[0]")" ]]; then
			files+=("$file")
		fi
	done
	if [[ ${files[*]} =~ 'modules/libcsharp-module.so' && -e 'modules/libcsharp-module.so' && ! ${files[*]} =~ 'AltV.Net.Host.dll' ]]; then
		_files=()
		for file in ${files[@]}
		do
		    if [ "$file" != 'modules/libcsharp-module.so' ]; then
		        _files+=("$file")
		    fi
		done
		files=("${_files[@]}")
		unset _files
	fi
	if [ ! -e 'start.sh' ]; then
		printAndLog "Server file start.sh not found, creating one . . . "
		printf '#!/bin/bash\nBASEDIR=$(dirname $0)\nexport LD_LIBRARY_PATH=${BASEDIR}\n./altv-server "$@"\n' > 'start.sh' && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
		chmod +x 'start.sh' || printAndLog "[$(date +%T)][Error] Failed to add execution permissions to file start.sh\e[39m\n" 'ERR'
	fi
	if [ $localBuild -ne $remoteBuild ]; then
		printAndLog "Server files update is available\n"
	elif [ "${#files[@]}" -ne 0 ]; then
		printAndLog "Server files are invalidated/corrupted, ${#files[@]} in total\n"
	else
		printAndLog "Server files are up-to-date, no action required\n"
	fi

	localBuild=$remoteBuild
	printf '{"branch":"%s","build":%d}' $localBranch $remoteBuild | jq '.' > 'update.cfg'
}
downloadFiles() {
	if [ "${#files[@]}" -eq 0 ]; then
		return
	fi
	for file in ${files[@]}
	do
		dlType="$(echo "${updateData}" | jq -r ".hashList.\"$file\"[1]")"
		outDir="$(dirname $file)"
		printAndLog "Downloading file $file . . . "
		if [[ "$noBackup" == 'false' && -e "$file" ]]; then
			mv "$file" "$file.old"
		fi
		wget "https://cdn.altv.mp/$dlType/$localBranch/x64_linux/${file}?build=$localBuild" -U 'AltPublicAgent' -P "$outDir/" -O "$file" -N -q && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
		if [ ! -e "$file" ]; then
			continue
		fi
		if [ -e "$file.old" ]; then
			chmod --reference="$file.old" "$file" || printAndLog "Failed to copy chmod to file $file\n" 'ERR'
			chmod -x "$file.old" || printAndLog "Failed to remove execution permissions from file $file.old\n" 'ERR'
		else
			chmod +x "$file" || printAndLog "Failed to add execution permissions to file $file\n" 'ERR'
		fi
	done
	validateFiles
}

if [ $noLogFile != true ]; then
	truncate -s 0 'update.log'
fi
if [ ! -e 'update.cfg' ]; then
	printf '{"branch":"stable"}' | jq '.' > 'update.cfg'
fi
updateCfg=$(cat 'update.cfg' | jq '.')
localBranch=$(echo "${updateCfg}" | jq -r '.branch')
[[ ! -n "$localBranch" || "$localBranch" != 'stable' && "$localBranch" != 'beta' && "$localBranch" != 'alpha' ]] && localBranch='stable'
fetchUpdateData
remoteBuild=$(echo "${updateData}" | jq -r '.latestBuildNumber')
localBuild=$(echo "${updateCfg}" | jq -r '.build')
[[ ! "$localBuild" =~ ^[0-9]+$ ]] && localBuild=$remoteBuild
validateFiles
downloadFiles
