pipeline {
  agent any

  stages {
      stage('Build Artifact') {
            steps {
              sh "mvn clean package -DskipTests=true"
              archive 'target/*.jar'
            }
        } 
      stage('Unit test') {
            steps {
              sh "mvn test" 
            }
            post {
              always {
                junit 'target/surefire-reports/*.xml'
                jacoco execPattern: 'target/jacoco.exec'
              }
            }
        }
      stage('Mutation Testing (PIT)') {
            steps {
              sh 'mvn org.pitest:pitest-maven:mutationCoverage'
            }
            post {
              always {
                  // Archive les rapports générés (XML + HTML)
                  archiveArtifacts artifacts: 'target/pit-reports/**', allowEmptyArchive: true
                  // Publie le rapport HTML dans l'interface Jenkins (nécessite le plugin HTML Publisher)
                  publishHTML(target: [
                      reportDir: 'target/pit-reports',
                      reportFiles: 'index.html',
                      reportName: 'PIT Mutation Report',
                      keepAll: true,
                      alwaysLinkToLastBuild: true,
                      allowMissing: false
                  ])
                }
            }
         }  
      stage('SonarQube -SAST') {
            steps {
              withSonarQubeEnv('SonarQube'){
                sh "mvn clean verify org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
                    -Dsonar.projectKey=numerica-application \
                    -Dsonar.projectName='numerica-application' \
                    -Dsonar.host.url=http://sonarqube.devsecops-local.click:9000 \
                    -Dsonar.token=sqp_8701b6cce98a7a431a3d86f32dfb17a0addb3a3f"
            } 
         }
      } 
      stage('Vulnerability Scan - Docker') {
            steps {
                sh "mvn org.owasp:dependency-check-maven:check"
            }
            post {
              always {
                dependencyCheckPublisher pattern: 'target/dependency-check-report.xml'
              }
            }
         }   
      stage('Docker Build and Push') {
          steps {
            withDockerRegistry([credentialsId: "docker-hub", url: ""]) {
                sh 'printenv'
                sh 'docker build -t ednoush01/numeric-app:""$GIT_COMMIT"" .'
                sh 'docker push ednoush01/numeric-app:""$GIT_COMMIT""'
                }
            }
        }	
      stage('Kubernetes Deployment - DEV') {
         steps {
           withKubeConfig([credentialsId: 'kubeconfig']) {
            sh "sed -i 's#replace#ednoush01/numeric-app:${GIT_COMMIT}#g' k8s_deployment_service.yaml"
            sh "kubectl apply -f k8s_deployment_service.yaml"
            }
         }
      }
    }
 }  