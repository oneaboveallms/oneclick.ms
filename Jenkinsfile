pipeline {
    agent any

    parameters {
        booleanParam(name: 'autoApprove', defaultValue: false, description: 'Automatically run apply or destroy without confirmation?')
        choice(name: 'action', choices: ['apply', 'destroy'], description: 'Select the action to perform')
    }

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_DEFAULT_REGION    = 'us-east-2'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/oneaboveallms/oneclick.ms.git'
            }
        }
        stage('Terraform init') {
            steps {
                sh 'terraform init'
            }
        }
        stage('Plan') {
            steps {
                script {
                    if (params.action == 'apply') {
                        sh 'terraform plan -out=tfplan'
                    } else if (params.action == 'destroy') {
                        sh 'terraform plan -destroy -out=tfplan'
                    }
                }
            }
        }
        stage('Terraform Execute') {
            steps {
                script {
                    if (params.action == 'apply') {
                        if (params.autoApprove) {
                            sh 'terraform apply -auto-approve tfplan'
                        } else {
                            sh 'terraform apply tfplan'
                        }
                    } else if (params.action == 'destroy') {
                        if (params.autoApprove) {
                            sh 'terraform destroy -auto-approve'
                        } else {
                            // Remove the '-auto-approve' flag if manual confirmation is desired
                            sh 'terraform destroy'
                        }
                    }
                }
            }
        }
        stage('Run Ansible Playbooks') {
            steps {
                sh 'ansible-playbook -i aws_ec2.yaml install.yaml'
            }
        }
    }
}
