#!/usr/bin/env bash

set -eu

docker_tag=
docker_tag_opt="--tag"
while [ $# -ne 0 ]; do
	case $1 in
		--debug)
			set -x
			;;
		-h|--help) cat >/dev/stderr <<-EOF
			Usage : $0 [version]
			    version : Either fill the .env file before executing this script or give the full wanted version as a parameter
			EOF
			exit 0
			;;
		--lts)
			docker_tag_opt="--lts"
			;;
		*) docker_tag="${1}";;
	esac
	shift
done

if [ -z "${docker_tag}" ]; then
	docker_tag=$(./tools/get_last_jenkins_docker_tag.sh ${docker_tag_opt})
fi

if [ ! -s ".env" ]; then
	cp .env.tmpl .env
fi
sed -i.prepareversionbackup -e '/VERSION/s/.*/VERSION='${docker_tag}'/' .env

. .env
composefile=docker-compose.yml
registry=${DOCKER_REGISTRY:-psykocat}
image=${registry:+${registry}/}jenkins
override_install_files=( "ref/jenkins.install.InstallUtil.lastExecVersion.override" "ref/jenkins.install.UpgradeWizard.state.override")
VERSION="${VERSION:?"You must provide a jenkins version !"}"
DOCKERFILE=${DOCKERFILE:?"You must provide a proper dockerfile name"}
DOCKERFILE=${DOCKERFILE:?"You must provide a proper dockerfile name"}
# On MAC, -i shall have an extension provided to work as in Linux
sed -i.prepareversionbackup -e '/VERSION/s/.*/VERSION='${VERSION}'/' .env.tmpl
sed -i.prepareversionbackup -e '/^\s*FROM/s%:.*%:'"${VERSION}"'%;/org.label-schema.name/s%.*%LABEL org.label-schema.name="'"${image}"'"%' "${DOCKERFILE}"
sed -i.prepareversionbackup -e '/image:\s*'"${registry}"'/s%image:.*%image: '"${image}"':${VERSION}%' "${composefile}"
sed -i.prepareversionbackup -e '/^\s*FROM/s%.*%FROM '"${image}"':'"${VERSION}"'%' "Dockerfile.tmpl"
for install_file in ${override_install_files[*]}; do
	echo ${VERSION%-*} > "${install_file}"
done
rm -vf *.prepareversionbackup .*.prepareversionbackup
git commit -m "Updating jenkins-base to version ${VERSION}" .env.tmpl "${DOCKERFILE}" "Dockerfile.tmpl" "${composefile}" ${override_install_files[@]}||true
# vim: noexpandtab:
