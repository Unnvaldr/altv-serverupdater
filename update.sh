#!/bin/bash
#
# Script Name: update.sh
#
# Author: Lhoerion
#
# Description: The following script compares SHA-1 hashes of remote and local files. If local file is missing or outdated, script automatically downloads it to script directory.
#              Old files are preserved as *.old. Script also keep track of current branch and build. 
#
# Run Information: This script is run manually.
# Dependencies: coreutils, wget, >=jq_1.4
#

BASEDIR=$(dirname $0)
if [ ! -e './update.cfg' ]; then
	touch './update.cfg'
	jq -n --arg branch stable '{"branch":"$branch"}' > './update.cfg'
fi
updateCfg=$(cat './update.cfg' |jq -r '.')
localBranch=$(echo "${updateCfg}" |jq -r '.branch')
[[ ! -n "$localBranch" || "$localBranch" != 'stable' && "$localBranch" != 'beta' ]] && localBranch="stable"
updateInfo=$(curl -s "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/update-info.json")
remoteBuild=$(echo "${updateInfo}" |jq -r '.latestBuildNumber')
localBuild=$(echo "${updateCfg}" |jq -r '.build')
[[ ! "$localBuild" =~ '^[0-9]+$' ]] && localBuild="$remoteBuild"
printf "[$(date +%T)] Current \e[92malt:V\e[0m build \e[33m#$localBuild\e[0m, branch \e[36m$localBranch\e[0m\n"
printf "[$(date +%T)] Latest \e[92malt:V\e[0m build \e[33m#$remoteBuild\e[0m, branch \e[36m$localBranch\e[0m\n"

if [[ ! -e './altv-server' || $(sha1sum './altv-server' |awk '{print $1}') != $(echo "${updateInfo}" |jq -r '.hashList."altv-server".hash') ]]; then
	printf "[$(date +%T)] File altv-server is outdated or missing, downloading . . . "
	if [ -e './altv-server' ]; then
		mv './altv-server' './altv-server.old'
	fi
	wget "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/altv-server" -P './' -q && printf 'done\n' || printf 'failed\n'
	if [ -e './altv-server.old' ]; then
		chmod --reference='./altv-server.old' './altv-server'
		chmod -x './altv-server.old'
	else
		chmod +x './altv-server'
		chmod -x './altv-server.old'
	fi
fi
if [[ ! -e './data/vehmodels.bin' || $(sha1sum './data/vehmodels.bin' |awk '{print $1}') != $(echo "${updateInfo}" |jq -r '.hashList."data/vehmodels.bin".hash') ]]; then
	printf "[$(date +%T)] File vehmodels.bin is outdated or missing, downloading . . . "
	if [ -e './data/vehmodels.bin' ]; then
		mv './data/vehmodels.bin' './data/vehmodels.bin.old'
	else 
		mkdir './data' -p
	fi
	wget "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/data/vehmodels.bin" -P './data' -q && printf 'done\n' || printf 'failed\n'
	if [ -e './data/vehmodels.bin.old' ]; then
		chmod --reference='./data/vehmodels.bin.old' './data/vehmodels.bin'
		chmod -x './data/vehmodels.bin.old'
	else
		chmod +x './data/vehmodels.bin'
		chmod -x './data/vehmodels.bin.old'
	fi
fi
if [[ ! -e './data/vehmods.bin' || $(sha1sum './data/vehmods.bin' |awk '{print $1}') != $(echo "${updateInfo}" |jq -r '.hashList."data/vehmods.bin".hash') ]]; then
	printf "[$(date +%T)] File vehmods.bin is outdated or missing, downloading . . . "
	if [ -e './data/vehmods.bin' ]; then
		mv './data/vehmods.bin' './data/vehmods.bin.old'
	else 
		mkdir './data' -p
	fi
	wget "https://alt-cdn.s3.nl-ams.scw.cloud/server/$localBranch/x64_linux/data/vehmods.bin" -P './data' -q && printf 'done\n' || printf 'failed\n'
	if [ -e './data/vehmods.bin.old' ]; then
		chmod --reference='./data/vehmods.bin.old' './data/vehmods.bin'
		chmod -x './data/vehmods.bin.old'
	else
		chmod +x './data/vehmods.bin'
		chmod -x './data/vehmods.bin.old'
	fi
fi
if [ ! -e './start.sh' ]; then
	printf '#!/bin/bash\nBASEDIR=$(dirname $0)\nexport LD_LIBRARY_PATH=${BASEDIR}\n./altv-server\n' > './start.sh'
	chmod +x './start.sh'
fi

jq -n --arg branch $localBranch --arg build $remoteBuild '{"branch":$branch,"build":$build}' > './update.cfg'
