// home-server CI/CD — validates and deploys the monitoring stack (monitoring/).
//
// Split: every branch/PR runs Validate (config + rule lint). Deploy runs on main only.
//
// The agent needs the Docker CLI + a usable host Docker daemon. No promtool/amtool
// install required — both run inside the pinned prom/* images via `docker run`.
//
// Jenkins credentials (secret text) — reused from the old discord-py pipeline, so nothing
// has to be recreated:
//   - grafana-admin-password            -> GRAFANA_ADMIN_PASSWORD (Grafana admin)
//   - discord-alertmanager-webhook-url  -> written to alertmanager/discord-webhook-url
//
// HOST-PATH GOTCHA: Jenkins runs in a container but drives the *host* Docker daemon, so the
// bind-mount paths in monitoring/docker-compose.yml are resolved by the host. The deploy
// rsyncs the tree to MONITORING_DEPLOY_PATH on the host and runs compose from there. The
// Jenkins container must have MONITORING_DEPLOY_PATH bind-mounted at the SAME path, and
// `rsync` must be installed in the Jenkins image.

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        PROM_IMAGE             = 'prom/prometheus:v3.11.3'
        ALERTMANAGER_IMAGE     = 'prom/alertmanager:v0.28.1'
        MONITORING_DEPLOY_PATH = '/home/izilov/Desktop/home-server-monitoring'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate') {
            // Lint Prometheus config + rules and Alertmanager config before anything ships.
            //
            // We copy files INTO throwaway containers with `docker cp` rather than
            // bind-mounting the workspace. Jenkins runs in a container but talks to the
            // *host* Docker daemon, so a `-v $WORKSPACE/...` mount source is resolved
            // against the host filesystem (where the workspace doesn't exist), giving the
            // container an empty dir. `docker cp` reads the files on the client side, so it
            // works regardless of the Jenkins-container / host-daemon split.
            //
            // The container command is set at `docker create` time and runs on `docker start -a`
            // (after the cp), which attaches and propagates the exit code so `set -e` catches
            // lint failures. prometheus/ is copied to /etc/prometheus so the config's
            // `rule_files: /etc/prometheus/rules/*.yml` resolves.
            steps {
                sh '''
                    set -e
                    pcid=""; acid=""
                    cleanup() { docker rm -f "$pcid" "$acid" >/dev/null 2>&1 || true; }
                    trap cleanup EXIT

                    pcid=$(docker create --entrypoint sh "$PROM_IMAGE" -c \
                        'promtool check config /etc/prometheus/prometheus.yml && promtool check rules /etc/prometheus/rules/*.yml')
                    docker cp monitoring/prometheus/. "$pcid:/etc/prometheus/"
                    docker start -a "$pcid"

                    acid=$(docker create --entrypoint amtool "$ALERTMANAGER_IMAGE" \
                        check-config /etc/alertmanager/alertmanager.yml)
                    docker cp monitoring/alertmanager/. "$acid:/etc/alertmanager/"
                    docker start -a "$acid"
                '''
            }
        }

        stage('Deploy') {
            when {
                anyOf {
                    branch 'main'
                    expression { (env.GIT_BRANCH ?: '') ==~ /(origin\/)?main/ }
                }
            }
            steps {
                echo "Deploying monitoring stack to ${MONITORING_DEPLOY_PATH}..."
                withCredentials([
                    string(credentialsId: 'grafana-admin-password',
                           variable: 'GRAFANA_ADMIN_PASSWORD'),
                    string(credentialsId: 'discord-alertmanager-webhook-url',
                           variable: 'DISCORD_WEBHOOK_URL')
                ]) {
                    sh '''
                        set -e
                        rsync -a --delete monitoring/ "$MONITORING_DEPLOY_PATH/"
                        umask 133
                        printf "%s" "$DISCORD_WEBHOOK_URL" > "$MONITORING_DEPLOY_PATH/alertmanager/discord-webhook-url"
                        docker compose -p monitoring -f "$MONITORING_DEPLOY_PATH/docker-compose.yml" up -d
                    '''
                }
            }
        }

        stage('Remove Dangling Images') {
            when {
                anyOf {
                    branch 'main'
                    expression { (env.GIT_BRANCH ?: '') ==~ /(origin\/)?main/ }
                }
            }
            steps {
                script {
                    def danglingImages = sh(script: 'docker images --filter "dangling=true" -q', returnStdout: true).trim()
                    if (danglingImages) {
                        sh "docker rmi ${danglingImages.replace('\n', ' ')}"
                    } else {
                        echo "No dangling images to remove."
                    }
                }
            }
        }

        stage('Verify') {
            when {
                anyOf {
                    branch 'main'
                    expression { (env.GIT_BRANCH ?: '') ==~ /(origin\/)?main/ }
                }
            }
            steps {
                script {
                    sleep(time: 5, unit: 'SECONDS')
                    ['prometheus', 'grafana', 'alertmanager', 'loki', 'tempo'].each { c ->
                        def status = sh(
                            script: "docker inspect --format='{{.State.Running}}' ${c} 2>/dev/null || echo missing",
                            returnStdout: true
                        ).trim()
                        if (status != 'true') {
                            error "Container ${c} is not running (status: ${status}). Check: docker logs ${c}"
                        }
                        echo "Container ${c} is running."
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline succeeded.'
        }
        failure {
            echo 'Pipeline failed. For the monitoring stack, check: docker compose -p monitoring ps'
        }
    }
}
