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
for arg in "$@"
do
	if [ $arg = '-noBackup' ]; then
		noBackup=true
		break
	fi
done
truncate -s 0 'update.log'
files=()
printAndLog() {
	if [ "$2" = 'ERR' ]; then
		printf "\e[91m[$(date +%T)][Error] $1\e[39m" |& tee -a 'update.log'
	elif [ "$2" = 'WARN' ]; then
		printf "\e[93m[$(date +%T)][Warning] $1\e[39m" |& tee -a 'update.log'
	elif [ "$2" = 'APP' ]; then
		printf "$1" |& tee -a 'update.log'
	else
		printf "[$(date +%T)] $1" |& tee -a 'update.log'
	fi
}
validateFiles() {
	files=()
	for file in $(echo $updateData | jq -r '.hashList | keys[]')
	do
		if [[ ! -e "$file" || $(sha1sum "$file" | awk '{print $1}') != "$(echo "${updateData}" | jq -r ".hashList.\"$file\"[0]")" ]]; then
			files+=("$file")
		fi
	done
	if [ ! -e 'start.sh' ]; then
		printAndLog "Server file start.sh not found, creating one . . . "
		printf '#!/bin/bash\nBASEDIR=$(dirname $0)\nexport LD_LIBRARY_PATH=${BASEDIR}\n./altv-server\n' > 'start.sh' && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
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
		fileName="$(basename $file)"
		if [[ $dlType != 'server' && $dlType != 'node-module' ]]; then
			file="$(basename $file)"
		fi
		printAndLog "Downloading file $outDir/$fileName . . . "
		if [[ "$noBackup" == 'false' && -e "$file" ]]; then
			mv "$file" "$file.old"
		fi
		wget "https://cdn.altv.mp/$dlType/$localBranch/x64_linux/$file" -U 'AltPublicAgent' -P "$outDir/" -N -q && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
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

if [ ! -e 'update.cfg' ]; then
	printf '{"branch":"stable"}' | jq '.' > 'update.cfg'
fi
updateCfg=$(cat 'update.cfg' | jq '.')
localBranch=$(echo "${updateCfg}" | jq -r '.branch')
[[ ! -n "$localBranch" || "$localBranch" != 'stable' && "$localBranch" != 'beta' && "$localBranch" != 'alpha' ]] && localBranch='stable'
updateData=$(curl -s "https://cdn.altv.mp/server/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
echo $updateData | jq empty 2>/dev/null
if [ $? -ne 0 ]; then
	printAndLog "Failed to check for update, try again later\n" 'ERR'
	exit
fi
str='. | to_entries | map(if .key=="hashList" then {"key":.key} + {"value":(.value | to_entries | map(. + {"key":"%s\(.key)","value":[.value, "%s"]}) | from_entries)} else . end) | from_entries'
updateTmp=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp 
updateTmp2=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp2
updateTmp3=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp3
echo $updateData | jq -c "$(printf "$str" '' 'server')" > $updateTmp
if [ "$localBranch" == 'beta' ]; then
	updateData2=$(curl -s "https://cdn.altv.mp/node-module/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData2 | jq empty 2>/dev/null
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for update, try again later\n" 'ERR'
		exit
	fi
	updateData3=$(curl -s "https://cdn.altv.mp/coreclr-module/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData3 | jq empty 2>/dev/null
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for update, try again later\n" 'ERR'
		exit
	fi
	echo $updateData2 | jq -c "$(printf "$str" '' 'node-module')" > $updateTmp2
	echo $updateData3 | jq -c "$(printf "$str" 'modules/' 'coreclr-module')" > $updateTmp3
	unset updateData2
	unset updateData3
else
	printAndLog "Checking for update of csharp-module and node-module is not possible yet in current branch\n" 'WARN'
fi
updateData=$(jq -s '.[1] * .[2] * .[0] | .hashList |= (to_entries | sort_by(.key) | from_entries) | .' $updateTmp $updateTmp2 $updateTmp3)
rm $updateTmp
rm $updateTmp2
rm $updateTmp3
remoteBuild=$(echo "${updateData}" | jq -r '.latestBuildNumber')
localBuild=$(echo "${updateCfg}" | jq -r '.build')
[[ ! "$localBuild" =~ ^[0-9]+$ ]] && localBuild=$remoteBuild
validateFiles
downloadFiles
