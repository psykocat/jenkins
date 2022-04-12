#!/usr/bin/env bash

set -eu

do_commit="yes"
while [ $# -ne 0 ]; do
	case $1 in
		--debug)
			set -x
			;;
		-h|--help) cat >/dev/stderr <<-EOF
			Usage : $0

			Update the list of plugins.txt with their associated versions
			EOF
			exit 0
			;;
		--no-commit)
			do_commit=""
			;;
		*);;
	esac
	shift
done

plugins_src=plugins.txt
plugins_dest=plugins_versioned.txt

plugins_tmp=$(mktemp -p ${PWD} XXXXXXXXXX_plugins.txt)

jenkins_version=$(sed -ne '2s/.*://p' Dockerfile)
jenkins_version=${jenkins_version%-alpine*}

if [ -z "${jenkins_version}" ]; then
	jenkins_version=latest
fi

function cleanup(){
    # Cleaning temp file
    rm -v -- "${plugins_tmp}"
}
trap cleanup EXIT ABRT

# Get latest plugins versions
echo "Dowloading updated plugins list."
curl -s https://updates.jenkins.io/current/update-center.json?version=${jenkins_version} \
  | sed 's|updateCenter.post(||g;s|);||g' \
  | jq -r '.plugins[] | (.name+":"+.version)' \
  | sort > "${plugins_tmp}"

echo "Cycling on new plugins only to update their versions."
rm -f "${plugins_dest}"
while read plugin; do
  echo "old : ${plugin}"
  newPlugin=$(grep "^${plugin}:" "${plugins_tmp}")
  echo "new : ${newPlugin}"
  echo "${newPlugin}" >> "${plugins_dest}"
done < <(cat "${plugins_src}")

if [ "${do_commit}" = "yes" ]; then
	git commit -m "Updating jenkins plugins" ${plugins_dest}||true
fi
#END
