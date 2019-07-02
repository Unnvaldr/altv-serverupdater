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

truncate -s 0 'update.log'
files=()
printAndLog() {
	if [ "$2" = 'ERR' ]; then
		printf "\e[91m[$(date +%T)][Error] $1\e[39m" |& tee -a 'update.log'
	elif [ "$2" = 'WARN' ]; then
		printf "\e[93m[$(date +%T)][Warning] $1\e[39m" |& tee -a 'update.log'
	elif [ "$2" = 'NDAT' ]; then
		printf "$1" |& tee -a 'update.log'
	else
		printf "[$(date +%T)] $1" |& tee -a 'update.log'
	fi
}
validateFiles() {
	files=()
	for file in {'altv-server','data/vehmodels.bin','data/vehmods.bin'}
	do
		if [[ ! -e "./$file" || $(sha1sum "./$file" |awk '{print $1}') != $(echo "${updateData}" |jq -r ".hashList.\"$file\".hash") ]]; then
			files+=("$file")
		fi
	done
	if [ ! -e './start.sh' ]; then
		printAndLog "Server file ./start.sh not found, creating one . . . "
		printf '#!/bin/bash\nBASEDIR=$(dirname $0)\nexport LD_LIBRARY_PATH=${BASEDIR}\n./altv-server' > './start.sh' && printAndLog 'done\n' 'NDAT' || printAndLog 'failed\n' 'NDAT'
		chmod +x './start.sh' || printAndLog "[$(date +%T)][Error] Failed to add execution permissions to file ./start.sh\e[39m\n" 'ERR'
	fi
	if [ $localBuild -ne $remoteBuild ]; then
    	printAndLog "Server files update is available\n"
	elif [ "${#files[@]}" -ne 0 ]; then
		printAndLog "Server files are invalidated/corrupted, ${#files[@]} in total\n"
	else
		printAndLog "Server files are up-to-date, no action required\n"
	fi

	localBuild="$remoteBuild"
	jq -n --arg branch $localBranch --arg build $remoteBuild '{"branch":$branch,"build":$build}' > './update.cfg'
}
downloadFiles() {
	if [ "${#files[@]}" -eq 0 ]; then
		return
	fi
	for file in ${files[@]}
	do
		parentDirectory=$(dirname "$file")
		printAndLog "Downloading file ./$file  . . . "
		if [ -e "./$file" ]; then
			mv "./$file" "./$file.old"
		fi
		wget "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/$file" -P "./$parentDirectory/" -q && printAndLog 'done\n' 'NDAT' || printAndLog 'failed\n' 'NDAT'
		if [ -e "./$file.old" ]; then
			chmod --reference="./$file.old" "./$file" || printAndLog "Failed to copy chmod to file ./$file\n" 'ERR'
			chmod -x "./$file.old" || printAndLog "Failed to remove execution permissions from file ./$file.old\n" 'ERR'
		else
			chmod +x "./$file" || printAndLog "Failed to add execution permissions to file ./$file\n" 'ERR'
		fi
	done
	validateFiles
}

BASEDIR=$(dirname $0)
if [ ! -e './update.cfg' ]; then
	touch './update.cfg'
	jq -n --arg branch stable '{"branch":"$branch"}' > './update.cfg'
fi
updateCfg=$(cat './update.cfg' |jq -r '.')
localBranch=$(echo "${updateCfg}" |jq -r '.branch')
[[ ! -n "$localBranch" || "$localBranch" != 'stable' && "$localBranch" != 'beta' ]] && localBranch='stable'
updateData=$(curl -s "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/update-info.json")
# coreclrData=$(curl -s 'https://api.github.com/repos/FabianTerhorst/coreclr-module/releases'$([[ $localBranch == 'stable' ]] && printf '/latest'))
remoteBuild=$(echo "${updateData}" |jq -r '.latestBuildNumber')
localBuild=$(echo "${updateCfg}" |jq -r '.build')
[[ ! "$localBuild" =~ ^[0-9]+$ ]] && localBuild="$remoteBuild"

validateFiles
downloadFiles
