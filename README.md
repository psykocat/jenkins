# Jenkins base installation and usage

This image is to be used as a base and customizable Jenkins docker image for a project. The idea behind this is simple : Each project shall have a "jenkins" repository. Its contents is, at minima, a simple way to run the template provided with an example of config file dedicated to the project but can be also its proper docker image, derivated from this image, with additional plugins and/or configuration files.

Below will be detailled the prerequisites and steps to setup your Jenkins.

For a lighter version of the process, a bash script is available :

```
curl -sSLO REPO_URL/get_jenkins.sh 
bash ./get_jenkins.sh
```

And follow the instructions printed at the end by the script.

If you want a fast available local jenkins without authentication process, use the two lines below:

```
cd jenkins_project
sed -i -e 's/\(_JENKINS_AUTH_METHOD_=\).*/\1disabled/' jenkins.config.env
./run.sh --local --automatic-preinstall
```

## For a project

Use the jenkins template as a basis and store it in your project's SCM repository.
By default, you have :
* A `.env`
* A `run.sh` script to run the docker images (Default options can be set in the beginning of the script, see the comments)
* A `jenkins.config.env` (with LDAP token needed to be added)
* A `Dockerfile` in case you need to customize the jenkins docker image (in this case don't forget to update your new image name in `docker-compose.yml`) with :
    * New plugins (In this case, by default, you need to create a `plugins.txt` file)
    * More packages
    * More init.groovy.d scripts (or overriding the ones by default)
* docker-compose files depending on your needs (as said above you can adapt them to your needs
* A `Jenkinsfile.disabled` file that can be renamed in Jenkinsfile to build your custom jenkins image.

It is **strongly** recommended to use the templated jenkins instead of the one in peps directly for a project in order not to depend of the full tree.

Like this if you ever need a simple update of version, just set it in the `.env` file with the wanted release and simply `./run.sh`

## Jenkins retrieval process

### Prerequisites

You need the following elements in order to use the jenkins on any server/your machine. These steps are currently valid for a Linux environment but may work for a Mac one too:
* `jq` if you need to use `global_shared_libraries.json`
* A docker daemon set up, to be properly operational you should listen to your Unix socket and on the secured port (tcp://`host.docker`:2376).
* docker-compose installed via a specific version found on [The release page](https://github.com/docker/compose/releases) or the following command ```sudo pip install -U docker-compose```.

### Fetch the docker image

Now you can fetch the latest (or a specific) version of the jenkins image, we try to match the official jenkins docker releases in our version but some holes may exists in between version tags.

1. Login to the registry if needed
2. Retrieve the wanted jenkins version in the tag list: `docker pull REGISTRY/jenkins:VERSION` (or :latest; version is of jenkins official docker alpine tags e.g: 2.146-alpine)
3. Run a temporary version of your jenkins to retrieve the template : `docker run -d --name jenkins_test REGISTRY/jenkins:VERSION` (You can also skip step 2 as it is implicitely done in step 3)
4. Copy the template dir in your current directory and remove your container: `docker cp jenkins_test:/templates/jenkins jenkins_project && docker rm -v -f jenkins_test`

Now `cd jenkins_project` and let's proceed to the execution.

## Execute your container

As you can see, you already have quite some files to play with. Some of them are `docker-compose.ELEM.yml` to execute your jenkins instance, with a `./run.sh` to wrap them up.

### Environment configs

There are 2 importants configuration files to preset before executing your instance :
1. The `.env` file will contains jenkins related workspace and version (normally the same as the one pulled previously, but can be incremented for further updates), take good care of your `dockerconfig_root` and `jenkins_home` variables as they are respectively the root path where will be stored all jenkins configs (env, ssh, ssl for docker certificates by default, among others you may add) and the jenkins home path where jenkins will store and persist everything during it's run process. A good commented example is to use the path `/usr/local/share/docker/configs/` for the root config.
2. The `jenkins/jenkins.config.env` file which will contains all wanted environment for jenkins execution, with some internal ones already set and ready to be filled. It is *strongly* recommended to store this file outside the project jenkins' repository and update the variable in the `.env` file accordingly. Please take care of keeping the mandatory `jenkins` parent dir.

### Docker-compose details

The docker-compose files have explicit names about when they need to be used but here's the description for each one:
* `docker-compose.yml` : Basic Jenkins execution with all environments, volumes set. Will also serve as default include for every other docker-compose files. Can be standalone if a service discovery is available on your server as it exposes its port.
* `docker-compose.local.yml` : Jenkins' local execution with 8080 port published and though accessible through `http://localhost:8080`
* `docker-compose.nginx.yml` : Jenkins' connection to any nginx proxy (with eventually letsencrypt too) with proper variables set (check your .env for this). This use nginx own network.
* `docker-compose.nginx_bridge.yml` : Jenkins' connection to any nginx proxy (with eventually letsencrypt too) with proper variables set (check your .env for this). This use docker global bridge network.

### Jenkins execution

The best way to execute by default these files, is through `run.sh` execution.
You can specify any docker combo to include with the adequat option like `./run.sh --local` or `./run.sh --nginx` or `./run.sh --nginx_bridge`.
Remaining options passed to `./run.sh` are docker-compose commands, with the default one being `up -d --force-recreate`.

When passing the -d option to daemonize the jenkins, as done by default, a `stop_jenkins_compose_session.sh` script will be generated to clean later on the session if needed.


## Jenkins maintenance

As simple usage, when a new release is available, you can execute both scripts to update your base jenkins version :
* `./tools/prepare_new_version.sh` will fetch the lattest tagged alpine version of official jenkins image and commit this infos (after updating scripts accordingly)
* `./tools/update_plugins_version.sh` updates and commits the list of versionned plugins (fixated to their latest version as the moment of the launch

If the deployment, for any reason, is to be made manually, use the script `./tools/build.sh` and `docker push` the image name generated at the end of the script.

## Warnings

* All ssh keys stored in `$dockerconfig_root/ssh` shall be usable by user 1000 to work for jenkins. The default file name, if no specific config file is set is `id_rsa`.
* To have the proper jenkins.config.env updates, it is strongly recommended to systematically redo the retrieval process instead of simply updating the VERSION variable in `.env`.
* Locally without gitlab you have to update `_JENKINS_AUTH_METHOD_=disabled` in `/usr/local/share/docker/config/jenkins/jenkins.config.env`.
