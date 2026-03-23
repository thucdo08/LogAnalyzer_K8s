pipeline {
    agent any

    environment {
        // Docker Registry nội bộ (thay bằng domain của bạn)
        REGISTRY = 'jfrog.dofuta.site'
        IMAGE_NAME_BE = "${REGISTRY}/loganalyzer-backend"
        IMAGE_NAME_FE = "${REGISTRY}/loganalyzer-frontend"
        // Git commit short SHA để tag image
        IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    echo "--- Building images with tag: ${IMAGE_TAG} ---"
                    sh "docker build -t ${IMAGE_NAME_BE}:${IMAGE_TAG} -t ${IMAGE_NAME_BE}:latest ./backend"
                    sh "docker build -t ${IMAGE_NAME_FE}:${IMAGE_TAG} -t ${IMAGE_NAME_FE}:latest ./frontend"
                }
            }
        }

        stage('Push to Private Registry') {
            steps {
                script {
                    // Registry nội bộ HTTP - cần --insecure-registry trong Docker daemon
                    sh "docker push ${IMAGE_NAME_BE}:${IMAGE_TAG}"
                    sh "docker push ${IMAGE_NAME_BE}:latest"
                    sh "docker push ${IMAGE_NAME_FE}:${IMAGE_TAG}"
                    sh "docker push ${IMAGE_NAME_FE}:latest"
                }
            }
        }

        stage('Update Helm values (GitOps)') {
            steps {
                script {
                    // Cập nhật image tag trong values.yaml → ArgoCD sẽ tự detect và sync
                    sh """
                        sed -i 's|tag: .*|tag: "${IMAGE_TAG}"|g' helm/loganalyzer/values.yaml
                        git config user.email "ci@loganalyzer"
                        git config user.name "Jenkins CI"
                        git add helm/loganalyzer/values.yaml
                        git commit -m "ci: update image tag to ${IMAGE_TAG} [skip ci]"
                        git push origin main
                    """
                }
            }
        }

        stage('Cleanup') {
            steps {
                sh "docker image prune -f"
            }
        }
    }

    post {
        success {
            echo "✅ Build thành công! ArgoCD sẽ tự động deploy trong ~3 phút."
        }
        failure {
            echo "❌ Build thất bại. Kiểm tra log ở trên."
        }
    }
}