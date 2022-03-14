#!/usr/bin/env bash

set -eu

_env_file=${JENKINS_ENV_FILE:-.env}

# Docker / Dockerfile won't handle symlink following so we cp the wanted files to create a jenkins template repository
jks_tpl=templates/jenkins

function cleanup(){
	rm -rf -- "${jks_tpl}"
}
trap cleanup EXIT

cleanup

do_push=
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
		-e|--env-file)
			shift
			_env_file=${1}
			;;
		--push)
			do_push=yes
			;;
		*);;
	esac
	shift
done

if [ -s "${_env_file}" ]; then
	set -a
	. "${_env_file}"
	set +a
fi

# Copy file list for jenkins template
for jfile in jenkins.config.env ${DOCKERFILE} docker-compose*.yml run.sh README.md "${_env_file}" .gitignore .editorconfig Jenkinsfile.disabled global_shared_libraries.json.example; do
    # Try first with a tmpl if it exists, otherwise the default file
    for jext in ".tmpl" ""; do
        base=${jfile}${jext}
        dest=${base%.tmpl}
        mkdir -p $(dirname ${jks_tpl}/${base})
        if [ -f "${base}" ]; then
            cp -vL ${base} ${jks_tpl}/${dest}
            break
        fi
    done
done

export WORKSPACE=${PWD}

docker-compose -f docker-compose.yml -f docker-compose.local.yml build --force-rm --no-cache --pull jenkins
tag_filename="${jks_tpl}/jenkins_release_tagname"
docker-compose -f docker-compose.yml -f docker-compose.local.yml config | yq -r '.services.jenkins.image' > "${tag_filename}"
tag_contents=$(cat "${tag_filename}")
docker tag "${tag_contents}" "${tag_contents%:*}:latest"

if [ "${do_push}" = "yes" ]; then
	docker-compose -f docker-compose.yml -f docker-compose.local.yml push -- jenkins
fi
#END
