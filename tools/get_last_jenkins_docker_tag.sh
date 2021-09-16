#!/usr/bin/env bash

set -eu

image_name=$(awk '/^FROM/{ sub(":.*", ""); print $2;}' Dockerfile)
tags_url="https://registry.hub.docker.com/v1/repositories/${image_name}/tags"
last_tag_match="[0-9].*-alpine$"
last_lts_match="[0-9].*lts-alpine$"
verbose=
matching_element="tag"

# Parse arguments
while [ $# -ne 0 ]; do
	case ${1} in
		--debug) set -x;;
		-v|--verbose) verbose="yes";;
		--lts) matching_element="lts";;
		--tag) matching_element="tag";;
		--)shift; break;;
		*) ;;
	esac
	shift;
done

jq_var="last_${matching_element}_match"

last_tag=$(curl -sSL "${tags_url}"|jq --arg match_repr "${!jq_var}" -r '.[]|select(.name|match($match_repr))|.name'|sort -V|tail -1)

if [ "${verbose}" = "yes" ]; then
    echo "Last tag for ${image_name} is '${last_tag}'"
else
    echo "${last_tag}"
fi
#END
