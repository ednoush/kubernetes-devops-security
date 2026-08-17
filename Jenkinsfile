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
            sh "sed -i 's#replace#dnoush01/numeric-app:${GIT_COMMIT}#g' k8s_deployment_service.yaml"
            sh "kubectl apply -f k8s_deployment_service.yaml"
          }
        }
     }   
  }
}