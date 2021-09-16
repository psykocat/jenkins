#!/usr/bin/env bash
set -eu

# parse arguments
usage(){
	cat > /dev/stderr <<-EOF
	Usage: ${0}

EOF
}
fatal(){
	echo >&2 $*
	exit 1
}
cleanup(){
	docker rm -v -f "${temp_img}" >/dev/null
}
trap cleanup EXIT ABRT
IMAGE_VERSION=${IMAGE_VERSION:-latest}
JENKINS_DIR=${JENKINS_DIR:-jenkins_project}
registry=${DOCKER_REGISTRY}
jenkins_image=${registry}/jenkins
temp_img=jenkins_template_retrieval
args=()
while [ $# -ne 0 ]; do
	case ${1} in
		--debug) set -x;;
		--)shift; break;;
		-h|-help|--help) usage; exit 1;;
		*) args+=("${1}");;
	esac
	shift;
done
echo "Logging to registry ${registry}"
docker login ${registry}

echo "Retrieving templated jenkins"
docker run -d --name ${temp_img} ${jenkins_image}:${IMAGE_VERSION}
docker cp ${temp_img}:/templates/jenkins "${JENKINS_DIR}"

echo "Setting up configuration"
cd "${JENKINS_DIR}"
# Keep original version name if latest is asked for easier future updates
if [ "${IMAGE_VERSION}" != "latest" ]; then
	sed -i.bak -e 's/^VERSION=.*/VERSION='${IMAGE_VERSION}'/' ./.env && rm -f ./.env.bak
fi
. ./.env
cat > /dev/stdout <<-EOF
Now you can create your jenkins container following these steps :

* cd ${JENKINS_DIR}
* ./run.sh --help (to get a list of possible choices for the --MODE option)
* ./run.sh --MODE by replacing mode with the wanted one

/!\ Be warned that by defaut the auth method is gitlab but no token is provided. /!\
Before running the containers for the first time, edit the file ${dockerconfig_root}/jenkins/jenkins.config.env and use EITHER OF these two steps :
* Set _JENKINS_AUTH_METHOD_ to disabled
* Fill _OAUTH_CLIENT_ID_ and _OAUTH_CLIENT_SECRET_ variables.

EOF
# vim: noexpandtab:
