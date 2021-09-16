#!/usr/bin/env bash
set -eu

### Custom Jenkins execution

# If your jenkins is launched systematically with the same options,
# set them after the "set --" to execute it only with ./run.sh
if [ $# -eq 0 ]; then
	set -- #INPUT_YOUR_CUSTOM_OPTIONS_HERE
fi
###

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
args=()
cmd="up"
clean_home=""
run_prehook=
no_pull=""
filelist=("docker-compose.yml")
modes_array=()
for dcmode in ${script_dir}/docker-compose.*.yml; do
	dcmode="${dcmode%.yml}"
	dcmode="${dcmode#*docker-compose.}"
	modes_array+=("--${dcmode}")
done

# Not really needed for jenkins images purpose as we match the jenkins source image version
image_tag=latest
if git rev-parse --git-dir &>/dev/null; then
	image_tag=$(git rev-parse --short HEAD)
fi
stop_script=${script_dir}/stop_jenkins_compose_session.sh

# We add jenkins home override to allow using a custom one instead
set -a
. ./.env
set +a
JENKINS_HOME="${JENKINS_HOME:-${jenkins_home}}"

# Useful for when --local option is passed
if [ -z "${WORKSPACE:-}" ]; then
	# Set a default workspace value to either the parent of the current git directory or the parent if no git directory is defined
	WORKSPACE=$(dirname "$(git rev-parse --show-toplevel)" || echo "${PWD}/../")
fi
export JENKINS_HOME WORKSPACE image_tag

function usage(){
	cat >&2 <<-EOF
	Usage: ./run.sh [--automatic-preinstall|--clean-home-before] [--MODE] [docker_compose_options]

	    Run a docker-compose with the docker-compose.yml file and the given docker-compose options.
	    By default this script does a docker-compose up of the current dir contents with a project name as jenkins, pulling newest images beforehand.

	    This script will also generate a ${stop_script} script used to do a docker-compose down with this current environment.
	    It is useful to cleanly stop the current containers generated if a -d option is provided.

	    --automatic-preinstall: Update jenkins.config.env and install ssh keys before running/updating jenkins container

	    --MODE: use additional docker-compose file.
	            Possible options are : $(echo "${modes_array[*]}"|sed -e 's/ / , /g') . (spaces are voluntarily set to ease copy)

	EOF
}

function __run_pre_hook(){
	# Get final ssh directory
	local ssh_keys_path=
	# Get final jenkins.config.env path (We cannot use docker-compose yet as it may error on absent jenkins.config.env)
	local jenkins_config_path=$(sed -e '/jenkins.config.env/!d;s/.* //' ${filelist[*]})

	if [ -s "${script_dir}/global_shared_libraries.json" ]; then
		sed -i.bak -e '/_JENKINS_GLOBAL_SHARED_LIBRARY_JSON_=/d' jenkins.config.env
		rm -f jenkins.config.env.bak
		echo "_JENKINS_GLOBAL_SHARED_LIBRARY_JSON_='$(jq -rcM '.' global_shared_libraries.json)'" >> jenkins.config.env
	fi
	### jenkins.config.env installation
	# Evaluate any variables inside the name
	jenkins_config_path=$(eval "echo ${jenkins_config_path}")
	if [ -z "${jenkins_config_path}" ]; then
		jenkins_config_path=${dockerconfig_root}/jenkins/jenkins.config.env
	fi
	. "${jenkins_config_path}" || . ./jenkins.config.env
	sh -c "mkdir -p $(dirname "${jenkins_config_path}"); cp jenkins.config.env '${jenkins_config_path}';"

	### SSH keys copy
	if [ -d "${script_dir}/ssh_keys" ]; then
		ssh_keys_path=$(${dc_cmd} config|sed -e '/\.ssh/!d;s/:.*//;s/.* //')
		# Copy ssh keys to appropriate directory and chown them to be usable by jenkins
		sh -c "mkdir -p ${ssh_keys_path}; cp ${script_dir}/ssh_keys/* ${ssh_keys_path}/; chown 1000:1000 -R ${ssh_keys_path}; chmod 644 ${ssh_keys_path}/*"
	fi

	### Docker registry login
	# We use set +x to hide passwords on the console
	if [ -n "${_DOCKER_REGISTRY_BASE_}" -a -n "${_DOCKER_REGISTRY_USER_}" ]; then
		(
		set +x
		. "${jenkins_config_path}"
		if [ -n "${_DOCKER_REGISTRY_PASSWORD_}" ]; then
			echo ${_DOCKER_REGISTRY_PASSWORD_}|docker login --username="${_DOCKER_REGISTRY_USER_}" --password-stdin "${_DOCKER_REGISTRY_BASE_}"
		else
			echo "Please input your docker registry password for ${_DOCKER_REGISTRY_BASE_} as ${_DOCKER_REGISTRY_USER_}"
			docker login --username="${_DOCKER_REGISTRY_USER_}" "${_DOCKER_REGISTRY_BASE_}"
		fi
		)
	fi
	if [ -z "${site_url}" ] && echo "${filelist[*]}"|grep -qe 'nginx'; then
		tput setaf 3
		echo "WARNING : site_url variable is empty in your .env file"
		tput sgr0
	fi
}
function __run_docker_compose(){
	if [ "${cmd}" = "up" ]; then
		# Create script to down session
		cat > "${stop_script}" <<-EOF
		#!/usr/bin/env bash
		set -a
		$(env|grep -ve "LS_COLORS"|sed -e '/ /s/=\(.*\)/="\1"/')
		set +a
		set -e
		${dc_cmd} down
		rm -f \${BASH_SOURCE[0]}
		EOF
		chmod +x "${stop_script}"
		if echo "${args[*]}"|grep -qwe '--down'; then
			${stop_script}
			return
		fi
		if [ "${no_pull}" != "yes" ]; then
			${dc_cmd} pull
		fi
		${dc_cmd} "${cmd}" "${args[@]}"
		if echo "${args[*]}"|grep -qwe '-d'; then
			# This is not automatically put at the end as if we pass -d option to the up, it will give back the hand and do the down after it...
			echo "To stop your jenkins session, please use the script ${stop_script}"
		else
			# If we are not in detached mode, auto down after the up
			${stop_script}
		fi
	else
		${dc_cmd} "${cmd}" "${args[@]}" $*
	fi
}

function cleanup(){
	ret=$?
	if [ ${ret} -ne 0 ]; then
		rm -f ${stop_script}
	fi
}
trap cleanup EXIT

# Configuration parsing
tmp_args=
while [ $# -ne 0 ]; do
	case ${1} in
		-h|-help|--help) usage; exit 0;;
		--debug) set -x;;
		--clean-home-before) clean_home="yes";;
		--automatic-preinstall) run_prehook="yes";;
		--latest) export image_tag="latest";;
		--no-pull) no_pull="yes";;
		--*)
			if [ -r "docker-compose.${1#--}.yml" ]; then
				filelist+=("docker-compose.${1#--}.yml")
			else
				tmp_args+=" ${1}"
			fi
			;;
		-h|-help|--help|help) usage; exit 0;;
		*) tmp_args+=" ${1}";;
	esac
	shift
done

set -- ${tmp_args}
# Set default arguments if no command / args is provided
if [ $# -eq 0 ]; then
	set -- up -d --force-recreate
fi

# Command parsing
while [ $# -ne 0 ]; do
	case ${1} in
		--) shift; break;;
		-*) args+=( "${1}" );;
		*) cmd=${1};;
	esac
	shift
done

dc_cmd='docker-compose'
for dfile in ${filelist[*]}; do
	dc_cmd="${dc_cmd} --file ${dfile}"
done

### Run automatic preinstallation
if [ "${run_prehook}" = "yes" ]; then
	__run_pre_hook
fi

### Clean home before to start anew
if [ "${clean_home}" = "yes" ]; then
	jenkins_home=$(${dc_cmd} config|grep -e 'JENKINS_HOME'|sed -e 's/.* //g')
	rm -rf "${jenkins_home}" || true
fi
__run_docker_compose
# vim: set noexpandtab:
