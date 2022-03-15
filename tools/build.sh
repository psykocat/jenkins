#!/usr/bin/env bash

set -eu

_env_file=${JENKINS_ENV_FILE:-.env}

# Docker / Dockerfile won't handle symlink following so we cp the wanted files to create a jenkins template repository
jks_tpl=templates/jenkins
files_to_remove=()
files_to_remove+=("${jks_tpl}")
do_push=

function cleanup(){
	rm -vrf -- "${files_to_remove[@]}"
}
trap cleanup EXIT

cleanup

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
_jks_custom_cfg="jenkins.config.env"

# Copy file list for jenkins template
for jfile in "${_jks_custom_cfg}" "${DOCKERFILE}" docker-compose*.yml run.sh README.md "${_env_file}" .gitignore .editorconfig Jenkinsfile.disabled global_shared_libraries.json.example; do
    # Try first with a tmpl if it exists, otherwise the default file
	_jext=".tmpl"
	_base="${jfile}"
	_dest="${jfile}"
	if [ -s "${jfile}${_jext}" ]; then
		_base="${jfile}${_jext}"
	fi
	mkdir -p $(dirname "${jks_tpl}/${_base}")
	if [ -s "${_base}" ]; then
		cp -vL "${_base}" "${jks_tpl}/${_dest}"
	fi
done

image_tag="${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}jenkins:${VERSION}"
image_latest="${image_tag%:*}:latest"

docker build -t "${image_tag}" -t "${image_latest}" -f "${DOCKERFILE}" .

if [ "${do_push}" = "yes" ]; then
	docker push "${image_tag}"
	docker push "${image_latest}"
fi
#END
