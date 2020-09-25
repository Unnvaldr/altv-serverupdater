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
# Dependencies: coreutils, wget, >=jq_1.4, pcregrep
#

noBackup=false
noLogFile=false
dryRun=false
silent=false
for arg in "$@"
do
	if [ $arg = '--no-logfile' ]; then
		noLogFile=true
	elif [ $arg = '--no-backup' ]; then
		noBackup=true
	elif [ $arg = '--dry-run' ]; then
		dryRun=true
	elif [ $arg = '--silent' ]; then
		silent=true
	fi
done
files=()
printAndLog() {
	if [[ "$silent" == false ]]; then
		if [ "$2" = 'ERR' ]; then
			printf "\e[91m[$(date +%T)][Error] $1\e[39m" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
		elif [ "$2" = 'WARN' ]; then
			printf "\e[93m[$(date +%T)][Warning] $1\e[39m" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
		elif [ "$2" = 'APP' ]; then
			printf "$1" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
		else
			printf "[$(date +%T)] $1" |& ([ $noLogFile != true ] && tee -a 'update.log' || cat)
		fi
	fi
}
semVerCmp() {
	declare -r "semVerRegex=^(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
	local matchA=(${1##v})
	local matchB=(${2##v})
	for i in {1..5}
	do
		matchA+=(`echo ${1##v} | pcregrep "-o$i" $semVerRegex`)
		matchB+=(`echo ${2##v} | pcregrep "-o$i" $semVerRegex`)
	done
	if [ ${1##v} == ${2##v} ]; then
		echo 0 && return 0
	fi
	if [ \( -z $matchA[4] \) -a \( ! -z $matchB[4] \) ]; then
		echo 1 && return 0
	elif [ \( ! -z $matchA[4] \) -a \( -z $matchB[4] \) ]; then
		echo -1 && return 0
	fi
	local i=0
	for a in ${matchA[@]}
	do
		local b="${matchB[$i]}"
		if [ \( $i -eq 2 \) -a \( \( -z $a \) -o \( -z $b \) \) ]; then
			continue
		fi
		if [[ $a > $b ]]; then
			echo 1 && return 0
		elif [[ $a < $b ]]; then
			echo -1 && return 0
		fi
		i=$((i + 1))
	done
	echo 0 && return 0
}
# fetchUpdateData() {
# 	updateData=$(curl -s "https://cdn.altv.mp/server/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
# 	echo $updateData | jq -e '.' >/dev/null 2>&1
# 	if [ $? -ne 0 ]; then
# 		printAndLog "Failed to check for update, try again later\n" 'ERR'
# 		exit
# 	fi
# 	str='. | to_entries | map(if .key=="hashList" then {"key":.key} + {"value":(.value | to_entries | map(. + {"value":[.value, "%s"]}) | from_entries)} else . end) | from_entries'
# 	updateTmp=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp 
# 	updateTmp2=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp2
# 	updateTmp3=$(mktemp '/tmp/update.sh.XXX') && echo '{}' > $updateTmp3
# 	echo $updateData | jq -c "$(printf "$str" 'server')" > $updateTmp
# 	moduleName=$([ $(echo "$updateData" | jq -r '.latestBuildNumber') -eq -1 -o $(echo "$updateData" | jq -r '.latestBuildNumber') -ge 1232 ] && echo 'js-module' || echo 'node-module');
# 	updateData2=$(curl -s "https://cdn.altv.mp/$moduleName/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
# 	echo $updateData2 | jq -e '.' >/dev/null 2>&1
# 	if [ $? -ne 0 ]; then
# 		printAndLog "Failed to check for $moduleName update\n" 'WARN'
# 	else
# 		echo $updateData2 | jq -c "$(printf "$str" "$moduleName")" > $updateTmp2
# 		unset updateData2
# 	fi
# 	updateData3=$(curl -s "https://cdn.altv.mp/coreclr-module/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
# 	echo $updateData3 | jq -e '.' >/dev/null 2>&1
# 	if [ $? -ne 0 ]; then
# 		printAndLog "Failed to check for csharp-module update\n" 'WARN'
# 	else
# 		if [[ $(echo $updateData3 | jq -c '.hashList | has("AltV.Net.Host.dll")') == false ]]; then
# 			updateData3=$(echo $updateData3 | jq '.hashList |= . + {"AltV.Net.Host.dll":"'$(printf "%0.s0" {1..40})'"}')
# 			updateData3=$(echo $updateData3 | jq '.hashList |= . + {"AltV.Net.Host.runtimeconfig.json":"'$(printf "%0.s0" {1..40})'"}')
# 		fi
# 		if [[ $(echo $updateData3 | jq -c '.hashList | has("modules/libcsharp-module.so")') == false ]]; then
# 			updateData3=$(echo $updateData3 | jq '.hashList |= . + {"modules/libcsharp-module.so":"'$(printf "%0.s0" {1..40})'"}')
# 		fi
# 		echo $updateData3 | jq -c "$(printf "$str" 'coreclr-module')" > $updateTmp3
# 		unset updateData3
# 	fi
# 	updateData=$(jq -s '.[0].latestBuildNumber as $b | .[0].version as $c | reduce .[] as $x ({}; . * $x) | .latestBuildNumber=$b | .version=$c' $updateTmp $updateTmp2 $updateTmp3)
# 	rm $updateTmp
# 	rm $updateTmp2
# 	rm $updateTmp3
# 	remoteBuild="$(echo "$updateData" | jq -r '.latestBuildNumber')"
# 	[[ $remoteBuild -eq -1 ]] && remoteBuild=$(echo "$updateData" | jq -r '.version')
# }
fetchUpdateData() {
	updateData=$(curl -s "https://cdn.altv.mp/server/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
	echo $updateData | jq -e '.' >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		printAndLog "Failed to check for update, try again later\n" 'ERR'
		exit
	fi
	str='. | to_entries | map(if .key=="hashList" then {"key":.key} + {"value":(.value | to_entries | map(. + {"value":[.value, "%s"]}) | from_entries)} else . end) | from_entries'
	local updateTmp=($(mktemp '/tmp/update.sh.XXX'))
	echo '{}' > ${updateTmp[0]}
	echo $updateData | jq -c "$(printf "$str" 'server')" > ${updateTmp[0]}
	for (( i=0; i < ${#modules[@]}; i++ ))
	do
		if [[ "${modules[$i]}" == 'csharp-module' ]]; then
			modules[$i]='coreclr-module'
		fi
		local moduleName=${modules[$i]}
		updateData=$(curl -s "https://cdn.altv.mp/$moduleName/$localBranch/x64_linux/update.json" -A 'AltPublicAgent')
		echo $updateData | jq -e '.' >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			printAndLog "Failed to check for $moduleName update\n" 'WARN'
		else
			if [[ "$moduleName" == 'csharp-module' ]]; then
				if [[ $(echo $updateData | jq -c '.hashList | has("AltV.Net.Host.dll")') == false ]]; then
					updateData=$(echo $updateData | jq '.hashList |= . + {"AltV.Net.Host.dll":"'$(printf "%0.s0" {1..40})'"}')
					updateData=$(echo $updateData | jq '.hashList |= . + {"AltV.Net.Host.runtimeconfig.json":"'$(printf "%0.s0" {1..40})'"}')
				fi
				if [[ $(echo $updateData | jq -c '.hashList | has("modules/libcsharp-module.so")') == false ]]; then
					updateData=$(echo $updateData | jq '.hashList |= . + {"modules/libcsharp-module.so":"'$(printf "%0.s0" {1..40})'"}')
				fi
			fi
			updateTmp+=($(mktemp '/tmp/update.sh.XXX'))
			echo '{}' > "${updateTmp[${#updateTmp[@]} - 1]}"
			echo $updateData | jq -c "$(printf "$str" "$moduleName")" > "${updateTmp[${#updateTmp[@]} - 1]}"
		fi
	done
	updateData=$(jq -s '.[0].latestBuildNumber as $b | .[0].version as $c | reduce .[] as $x ({}; . * $x) | .latestBuildNumber=$b | .version=$c' ${updateTmp[@]})
	remoteBuild="$(echo "$updateData" | jq -r '.latestBuildNumber')"
	[[ $remoteBuild -eq -1 ]] && remoteBuild=$(echo "$updateData" | jq -r '.version')
}
validateFiles() {
	files=()
	for file in $(echo $updateData | jq -r '.hashList | keys[]')
	do
		if [[ ! -e "$file" || $(sha1sum "$file" | awk '{print $1}') != "$(echo "$updateData" | jq -r ".hashList.\"$file\"[0]")" ]]; then
			files+=("$file")
		fi
	done
	# if [ ! -e 'start.sh' ]; then
	# 	printAndLog "Server file start.sh not found, creating one . . . "
	# 	if [[ "$dryRun" == false ]]; then
	# 		printf '#!/bin/bash\nBASEDIR=$(dirname $0)\nexport LD_LIBRARY_PATH=${BASEDIR}\n./altv-server "$@"\n' > 'start.sh' && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
	# 		chmod +x 'start.sh' || printAndLog "[$(date +%T)][Error] Failed to add execution permissions to file start.sh\e[39m\n" 'ERR'
	# 	else
	# 		printAndLog 'done\n' 'APP'
	# 	fi
	# fi
	if [ ! -e 'server.cfg' ]; then
		printAndLog "Server file server.cfg not found, creating one . . . "
		if [[ "$dryRun" == false ]]; then
			printf 'name: "alt:V Server"\nhost: 0.0.0.0\nport: 7788\nplayers: 128\n#password: ultra-password\nannounce: false\n#token: YOUR_TOKEN\ngamemode: Freeroam\nwebsite: example.com\nlanguage: en\ndescription: "alt:V Sample Server"\nmodules: [\n  \n]\nresources: [\n  \n]\n' > 'server.cfg' && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
		else
			printAndLog 'done\n' 'APP'
		fi
	fi
	if [[ ! $localBuild =~ ^[0-9]+$ || $localBuild -ge 1232 ]]; then
		local nodeExist=$([ -e 'libnode.so.72' ] && echo true || echo false)
		local moduleExist=$([ -e 'modules/libnode-module.so' ] && echo true || echo false)
		if [[ "$nodeExist" == true || "$moduleExist" == true ]]; then
			printAndLog "Found old node-module files, removing . . . "
			if [[ "$dryRun" == false ]]; then
				local result1=true
				local result2=true
				if [[ "$nodeExist" == true ]]; then
					rm -f 'libnode.so.72'
					result1=$([[ "$?" -eq 0 ]] && echo true || echo false)
				fi
				if [[ "$moduleExist" == true ]]; then
					rm -f 'modules/libnode-module.so'
					result2=$([[ "$?" -eq 0 ]] && echo true || echo false)
				fi
				if [[ "$result1" == true && "$result2" == true ]]; then
					printAndLog 'done\n' 'APP'
				else
					printAndLog 'failed\n' 'APP'
				fi
			else
				printAndLog 'done\n' 'APP'
			fi
		fi
	fi
	if [ $localBuild != $remoteBuild ]; then
		printAndLog "Server files update is available\n"
	elif [ "${#files[@]}" -ne 0 ]; then
		printAndLog "Server files are invalidated/corrupted, ${#files[@]} in total\n"
	else
		printAndLog "Server files are up-to-date, no action required\n"
	fi

	if [[ "$dryRun" == false ]]; then
		localBuild=$remoteBuild
		modulesTemp=""
		for (( i=0; i < ${#modules[@]}; i++ ))
		do
			modulesTemp+="\"${modules[$i]}\""
			if [ $(($i + 1)) -ne ${#modules[@]} ]; then
				modulesTemp+=','
			fi
		done
		if [[ $localBuild =~ ^[0-9]+$ ]]; then
			printf '{"branch":"%s","build":%d,"modules":[%s]}' $localBranch $localBuild $modulesTemp | jq '.' > 'update.cfg'
		else
			printf '{"branch":"%s","build":"%s","modules":[%s]}' $localBranch $localBuild $modulesTemp | jq '.' > 'update.cfg'
		fi
	fi
}
downloadFiles() {
	if [ "${#files[@]}" -eq 0 ]; then
		return
	fi
	for file in ${files[@]}
	do
		dlType="$(echo "$updateData" | jq -r ".hashList.\"$file\"[1]")"
		outDir="$(dirname $file)"
		printAndLog "Downloading file $file . . . "
		if [[ "$dryRun" == false ]]; then
			if [[ "$noBackup" == false && -e "$file" ]]; then
				mv "$file" "$file.old"
			fi
			if [[ ! -e "$outDir/" ]]; then
				mkdir -p "$outDir/"
			fi
			wget "https://cdn.altv.mp/$dlType/$localBranch/x64_linux/${file}?build=$localBuild" -U 'AltPublicAgent' -O "$file" -N -q && printAndLog 'done\n' 'APP' || printAndLog 'failed\n' 'APP'
			if [ ! -e "$file" ]; then
				continue
			fi
			if [ -e "$file.old" ]; then
				chmod --reference="$file.old" "$file" || printAndLog "Failed to copy chmod to file $file\n" 'ERR'
				chmod -x "$file.old" || printAndLog "Failed to remove execution permissions from file $file.old\n" 'ERR'
			else
				chmod +x "$file" || printAndLog "Failed to add execution permissions to file $file\n" 'ERR'
			fi
		else
			printAndLog 'done\n' 'APP'
		fi
	done
	validateFiles
}

if [ $noLogFile != true ]; then
	truncate -s 0 'update.log'
fi
if [[ ( "$dryRun" == false ) && ( ! -e 'update.cfg' ) ]]; then
	printf '{"branch":"release","modules":["js-module"]}' | jq '.' > 'update.cfg'
fi
updateCfg=$([[ -e 'update.cfg' ]] && cat 'update.cfg' || printf '{"branch":"release","modules":["js-module"]}' | jq '.')
localBranch=$(echo "$updateCfg" | jq -r '.branch')
[[ ! -n "$localBranch" || "$localBranch" != 'release' && "$localBranch" != 'rc' && "$localBranch" != 'dev' ]] && localBranch='release'
modules=($(echo "$updateCfg" | jq -r '.modules' | tr -d '[],"'))
fetchUpdateData
localBuild="$(echo "$updateCfg" | jq -r 'if .build == null then empty else .build end')"
[[ -z $localBuild || $localBuild == "-1" ]] && localBuild=$remoteBuild
printAndLog "Current version: $localBuild\n"
printAndLog "Latest version: $remoteBuild\n"
validateFiles
downloadFiles
