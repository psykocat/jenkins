# You shall build this docker image through the script ./tools/build.sh
FROM jenkins/jenkins:2.339-alpine

LABEL maintainer="Psyko Cat"
LABEL org.label-schema.name="psykocat/jenkins"
LABEL org.label-schema.description="Wrapper for Jenkins base with configuration done automatically"

ARG pluginfile=plugins_versioned.txt

USER root
RUN apk add --no-cache curl tar jq git shadow openssl \
    python3 \
    py3-pip \
    python3-dev libffi-dev openssl-dev gcc libc-dev make \
    ca-certificates

# Install pip
ARG PIP_VERSION="21.2.4"
RUN pip3 install -U pip==${PIP_VERSION}

# Glibc install
ARG glibc_version="2.34-r0"
RUN curl -sSLo /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub \
    && curl -sSLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${glibc_version}/glibc-${glibc_version}.apk \
    && apk add glibc-${glibc_version}.apk && rm glibc-${glibc_version}.apk \
    && curl -sSLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${glibc_version}/glibc-bin-${glibc_version}.apk \
    && apk add glibc-bin-${glibc_version}.apk && rm glibc-bin-${glibc_version}.apk

COPY download_and_install.sh /tmp/download_and_install.sh
RUN chmod a+x /tmp/download_and_install.sh

# Docker install (docker cli + docker-compose)
ARG DOCKER_VERSION="20.10.8"
ARG DOCKER_COMPOSE_VERSION="1.29.2"
RUN /tmp/download_and_install.sh docker https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz 1 \
    && curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
    && chmod 755 /usr/local/bin/docker-compose

# Rancher install (cli + compose)
# ARG RANCHER_CLI_VERSION="v0.6.4"
# ARG RANCHER_COMPOSE_VERSION="v0.12.5"
# RUN /tmp/download_and_install.sh rancher https://releases.rancher.com/cli/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz 1 \
#     && /tmp/download_and_install.sh rancher-compose https://releases.rancher.com/compose/${RANCHER_COMPOSE_VERSION}/rancher-compose-linux-amd64-${RANCHER_COMPOSE_VERSION}.tar.gz 1

# Kube install (kubectl + helm + compose)
# ARG KUBECTL_VERSION="v1.10.3"
# ARG KOMPOSE_VERSION="v1.14.0"
# ARG HELM_VERSION="v2.9.1"
# RUN curl -fsSLo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && chmod a+x /usr/local/bin/kubectl \
#     && curl -fsSLo /usr/local/bin/kompose https://github.com/kubernetes/kompose/releases/download/${KOMPOSE_VERSION}/kompose-linux-amd64 && chmod a+x /usr/local/bin/kompose \
#     && /tmp/download_and_install.sh helm https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz 1

# Install plugins (put to last as it is the longest part and the most susceptible to break)
COPY ${pluginfile} plugins_base.txt
RUN bash install-plugins.sh $(echo $(cat plugins_base.txt)) && for _file in /usr/share/jenkins/ref/plugins/*.jpi ; do mv ${_file} "${_file}.override" ; done

COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d
COPY ref/* /usr/share/jenkins/ref/

COPY templates /templates
RUN chown -R jenkins:jenkins /templates

# Add jenkins user in group docker in case of
RUN usermod -a -G 999 jenkins

USER jenkins
