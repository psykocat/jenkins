//// Custom part to be updated
// Git scheme for repo authentification (http(s), ssh, ...)
def git_scheme = "http"
// Can accept pure branch names like develop or with wildcards like release/*
def jenkinsfileBranchesPattern = "develop master release/*"
//// End of custom part to be updated

def url_creds_map = [
    "http": [
        "url_base": "TOBEFILLEDBELOW",
        "credentials": "bitbucket-api-credentials"
    ],
    "https": [
        "url_base": "TOBEFILLEDBELOW",
        "credentials": "bitbucket-api-credentials"
    ],
    "ssh": [
        "url_base": "TOBEFILLEDBELOW",
        "credentials": "ssh-jenkins-user-keys"
    ]
]
def credsId = null
def dslContents = []

// Trim leading and trailing quotes and spaces from string
def trimQSFrom(string) {
    def newStr = string
    // We look for any combination mixing quotes and spaces but only leading or trailling a string
    newStr = newStr.replaceFirst(/^\\s*["']*\\s*/, '')
    newStr = newStr.replaceFirst(/\\s*["']*\\s*$/, '')
    return newStr
}

def jsonParseBitbucket(url) {
    def stdout = null
    def jsonOutput = null
    def bburl = null
    withCredentials([usernamePassword(credentialsId: 'bitbucket-api-credentials', passwordVariable: 'access_key', usernameVariable: 'user_key')]) {
        if (url.startsWith("http")) {
            bburl = trimQSFrom(url)
        }
        else {
            bburl = trimQSFrom(env._BITBUCKET_REST_API_BASEURL_ + "/" + url)
        }
        println("Processing ${bburl}")
        stdout = sh returnStdout: true, script: "curl -su '${user_key}:${access_key}' '${bburl}'"
    }
    jsonOutput = readJSON text: stdout.trim()
    return jsonOutput
}

pipeline {
    agent any
	parameters {
		booleanParam(name: 'IGNORE_EXISTING', defaultValue: true, description: 'Ignore existing jobs (do not force recreation)')
    }
    // If you need the checkout scm stage, uncomment this option, otherwise keep as is.
    //options {
    //    skipDefaultCheckout(true)
    //}
    stages {
        //stage('checkout code from SCM') {
        //    steps {
        //        script {
        //            scmInfos = checkout scm
        //            gitCommit = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        //            def baseRepo = scmInfos.GIT_URL.replaceFirst('/[^/]+$', "")
        //        }
        //    }
        //}
        stage('Retrieve Project infos') {
            steps {
                script {
                    def group = env._PROJECT_NAME_
                    // Get adequat credentials according to repo protocol
                    def projects = jsonParseBitbucket("projects/${group}/repos/?limit=1000")?.values
                    if(!projects){
                        error("Failed to retrieve projects informations")
                    }
                    // Fill dynamically projects base urls according to REST API output
                    for (clone in projects[0].links.clone){
                        def baseHref = clone.href.replaceFirst('[^/]+$', "")
                            if(clone.name.contains("http")){
                                // Remove the user part
                                baseHref = baseHref.replaceFirst('/[^@/]+@', "/")
                            }
                        url_creds_map[clone.name]["url_base"] = baseHref
                    }
                    def credentialsName = url_creds_map[git_scheme]["credentials"]

                    for (project in projects) {
                        println("Processing project ${project.slug}")
                        def projectdetails = jsonParseBitbucket("projects/${group}/repos/${project.slug}/browse")
                        // Filter to have only *Jenkinsfiles*
                        // The chain of ? is for 'proceed if not null, it must escalate down to every methods to be effective
                        def jenkinsFiles = projectdetails?.children?.values?.path?.toString?.findAll { it.contains("Jenkinsfile") } ?: []
                        def url_to_repo = url_creds_map[git_scheme]["url_base"] + "${project.slug}.git"
                        url_to_repo = url_to_repo.toString()
                        def createdJobs = []
                        for (file in jenkinsFiles) {
                            if ( file.equals("Jenkinsfile") ) {
                                // Basic jenkins file that will be executed for every branches
                                createdJobs.add(project.slug)
                                dslContents.add("""
                                    multibranchPipelineJob("${project.slug}") {
                                        branchSources {
                                            branchSource {
                                                source {
                                                    git {
                                                        remote("${url_to_repo}")
                                                        credentialsId("${credentialsName}")
                                                        traits {
                                                            headWildcardFilter {
                                                               includes("${jenkinsfileBranchesPattern}")
                                                               excludes("")
                                                            }
                                                            // Run "git remote prune" for each remote, to prune obsolete local branches.
                                                            pruneStaleBranchTrait()
                                                            // Delete the contents of the workspace before building, ensuring a fully fresh workspace.
                                                            wipeWorkspaceTrait()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        triggers {
                                            periodic(1)
                                        }
                                        orphanedItemStrategy {
                                            discardOldItems {
                                                numToKeep(30)
                                                daysToKeep(20)
                                            }
                                        }
                                    }
                                """)
                            } else if ( file.equals("Jenkinsfile.test") ) {
                                // This file is for tests, single (default) branch pipeline, trigger by default every two hours.
                                createdJobs.add("${project.slug}-test")
                                dslContents.add("""
                                    pipelineJob("${project.slug}-test") {
                                        definition {
                                            cpsScm {
                                                scm {
                                                    git {
                                                        branch("${projectdetails.revision}")
                                                        remote {
                                                            url("${url_to_repo}")
                                                            credentials("${credentialsName}")
                                                        }
                                                    }
                                                }
                                                scriptPath("${file}")
                                            }
                                        }
                                        triggers {
                                            cron('120')
                                        }
                                        //// Manages how long to keep records of the builds.
                                        //logRotator {
                                        //    // If specified, artifacts from builds older than this number of days will be deleted, but the logs, history, reports, etc for the build will be kept.
                                        //    artifactDaysToKeep(int artifactDaysToKeep)
                                        //    // If specified, only up to this number of builds have their artifacts retained.
                                        //    artifactNumToKeep(int artifactNumToKeep)
                                        //    // If specified, build records are only kept up to this number of days.
                                        //    daysToKeep(int daysToKeep)
                                        //    // If specified, only up to this number of build records are kept.
                                        //    numToKeep(int numToKeep)
                                        //}
                                    }""")
                            } else if ( file.equals("Jenkinsfile.deploy") ) {
                                // This is for untriggered, manual launch pipelines (usually for deliveries or pipelines trigger by other jobs)
                                // Check whether a job within the same project already exists to prefix this one with job-
                                def deployJobName = "${project.slug}".toString()
                                if (createdJobs.contains(deployJobName)) {
                                    deployJobName = "job-${project.slug}"
                                }
                                createdJobs.add("${deployJobName}")
                                // create the new job
                                dslContents.add("""
                                    pipelineJob("${deployJobName}") {
                                        definition {
                                            cpsScm {
                                                scm {
                                                    git {
                                                        branch("${projectdetails.revision}")
                                                        remote {
                                                            url("${url_to_repo}")
                                                            credentials("${credentialsName}")
                                                        }
                                                    }
                                                }
                                                scriptPath("${file}")
                                            }
                                        }
                                        //// Manages how long to keep records of the builds.
                                        //logRotator {
                                        //    // If specified, artifacts from builds older than this number of days will be deleted, but the logs, history, reports, etc for the build will be kept.
                                        //    artifactDaysToKeep(int artifactDaysToKeep)
                                        //    // If specified, only up to this number of builds have their artifacts retained.
                                        //    artifactNumToKeep(int artifactNumToKeep)
                                        //    // If specified, build records are only kept up to this number of days.
                                        //    daysToKeep(int daysToKeep)
                                        //    // If specified, only up to this number of build records are kept.
                                        //    numToKeep(int numToKeep)
                                        //}
                                    }
                                """)
                            }
                        }
                    }
                }
            }
        }
        stage('Create jobs') {
            when { not { equals expected: 0, actual: dslContents.size() } }
            steps {
                script {
                    jobDsl sandbox:true, ignoreExisting: params.IGNORE_EXISTING, scriptText: dslContents.join("""\n""")
                }
            }
        }
    }
}
