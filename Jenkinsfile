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
        stage('Docker Build and Push') {
            steps {
              withDockerRegistry([credentialsId: "docker-hub", url: ""]) {
                sh 'printenv'
                sh 'docker build -t siddharth67/numeric-app:24aaa35dab9d9367f8518a0b3a245490d763f2c0:""$GIT_COMMIT"" .'
                sh 'docker push siddharth67/numeric-app:""$GIT_COMMIT""'
                }
            }
        }	  
    }
}