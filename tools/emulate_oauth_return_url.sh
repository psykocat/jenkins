#!/usr/bin/env bash
set -eu

for domain in $*; do
	for scheme in http https; do
		echo "${scheme}://${domain}/securityRealm/finishLogin"
	done
done
#END
