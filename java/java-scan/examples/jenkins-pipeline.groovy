// Jenkins Pipeline 集成示例

pipeline {
    agent any
    
    environment {
        SCANNER_IMAGE = 'your-registry/auth-scanner:latest'
        MAVEN_OPTS = '-Dmaven.repo.local=.m2/repository'
    }
    
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }
        
        stage('Security Scan') {
            steps {
                script {
                    // 查找构建的 JAR 文件
                    def jarFile = sh(
                        script: 'find target -name "*.jar" -not -name "*-sources.jar" | head -1',
                        returnStdout: true
                    ).trim()
                    
                    if (!jarFile) {
                        error "未找到 JAR 文件"
                    }
                    
                    // 使用 Docker 运行扫描
                    sh """
                        docker run --rm \
                            -v \$(pwd):/workspace \
                            -w /workspace \
                            ${SCANNER_IMAGE} \
                            ${jarFile} src/main/resources reports true
                    """
                }
            }
            post {
                always {
                    // 发布扫描报告
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'reports',
                        reportFiles: '*.json',
                        reportName: 'Auth Scan Report'
                    ])
                    
                    // 归档报告文件
                    archiveArtifacts artifacts: 'reports/*.json', allowEmptyArchive: true
                }
                failure {
                    // 发送通知
                    emailext (
                        subject: "认证扫描失败: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                        body: "认证扫描检测到安全问题，请查看报告: ${env.BUILD_URL}",
                        to: "${env.CHANGE_AUTHOR_EMAIL}"
                    )
                }
            }
        }
        
        stage('Deploy') {
            when {
                allOf {
                    branch 'main'
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                echo '部署到生产环境...'
                // 部署逻辑
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
    }
}