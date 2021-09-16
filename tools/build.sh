#!/usr/bin/env bash

set -e

set -a
. .env
set +a

# Docker / Dockerfile won't handle symlink following so we cp the wanted files to create a jenkins template repository
jks_tpl=templates/jenkins

function cleanup(){
	rm -rf -- "${jks_tpl}"
}
trap cleanup EXIT

cleanup

# Copy file list for jenkins template
for jfile in jenkins.config.env ${DOCKERFILE} docker-compose*.yml run.sh README.md .env .gitignore .editorconfig Jenkinsfile.disabled global_shared_libraries.json.example; do
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

WORKSPACE=$PWD docker-compose -f docker-compose.yml -f docker-compose.local.yml build --force-rm --no-cache --pull jenkins
tag_filename="${jks_tpl}/jenkins_release_tagname"
WORKSPACE=$PWD docker-compose -f docker-compose.yml -f docker-compose.local.yml config | yq -r '.services.jenkins.image' > "${tag_filename}"
tag_contents=$(cat "${tag_filename}")
docker tag "${tag_contents}" "${tag_contents%:*}:latest"

if [ "${1,,}" = "push" ]; then
	WORKSPACE=$PWD docker-compose -f docker-compose.yml -f docker-compose.local.yml push -- jenkins
fi
#END
