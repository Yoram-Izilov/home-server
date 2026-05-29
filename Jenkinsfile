// home-server CI/CD — deploys the monitoring stack (monitoring/).
//
// The agent needs the Docker CLI, a usable host Docker daemon, and rsync.
//
// Jenkins credentials (secret text) — reused from the old discord-py pipeline, so nothing
// has to be recreated:
//   - grafana-admin-password            -> GRAFANA_ADMIN_PASSWORD (Grafana admin)
//   - discord-alertmanager-webhook-url  -> written to alertmanager/discord-webhook-url
//
// HOST-PATH GOTCHA: Jenkins runs in a container but drives the *host* Docker daemon, so the
// bind-mount paths in monitoring/docker-compose.yml are resolved by the host. The deploy
// rsyncs the tree to MONITORING_DEPLOY_PATH on the host and runs compose from there. The
// Jenkins container must have MONITORING_DEPLOY_PATH bind-mounted at the SAME path (owned by
// the jenkins UID), and `rsync` must be installed in the Jenkins image.
//
// Config linting is not run here — validate locally before pushing with the commands in
// CLAUDE.md ("Verifying changes") or the sync-monitoring-config skill.

pipeline {
    agent any

    environment {
        MONITORING_DEPLOY_PATH = '/home/izilov/Desktop/home-server-monitoring'
    }

    stages {
        stage('Deploy') {
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
        always {
            echo 'Pipeline completed.'
        }
        success {
            echo 'Pipeline succeeded.'
        }
        failure {
            echo 'Pipeline failed. For the monitoring stack, check: docker compose -p monitoring ps'
        }
    }
}
