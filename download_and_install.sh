#!/bin/sh
set -eu

BINARY_NAME="${1}"
APP_URL="${2}"
STRIP_LEVEL="${3}"
strip_opt=""

if [ -n "${STRIP_LEVEL}" ]; then
    strip_opt="--strip-components=${STRIP_LEVEL}"
fi

destdir=/usr/local/share/${BINARY_NAME}

mkdir -p ${destdir}
curl -fsSL ${APP_URL} | tar -C ${destdir} -xz ${strip_opt}

if [ -f "${destdir}/${BINARY_NAME}" ]; then
    chmod a+x ${destdir}/${BINARY_NAME}
    ln -fs ${destdir}/${BINARY_NAME} /usr/local/bin/${BINARY_NAME}
fi
#END
