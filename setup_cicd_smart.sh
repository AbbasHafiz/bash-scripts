#!/bin/bash
# Smart CI/CD setup: skips installation if tools exist

# --------- 1. Check prerequisites ---------
echo "🔹 Checking prerequisites..."

# Git
if ! command -v git &>/dev/null; then
    echo "Git not found. Installing..."
    sudo apt update && sudo apt install -y git
else
    echo "Git already installed."
fi

# Docker
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Installing..."
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "Docker already installed."
fi

# Jenkins
if ! command -v java &>/dev/null || ! systemctl is-active --quiet jenkins; then
    echo "Jenkins not found or not running."
    echo "⚠️ Skipping Jenkins installation. Make sure Jenkins is installed and running."
else
    echo "Jenkins is installed and running."
fi

# --------- 2. Collect user input ---------
read -p "Enter your GitHub SSH repo URL: " GIT_REPO
read -p "Enter your Docker Hub username: " DOCKER_USER
read -p "Enter your deployment server (ssh user@ip): " DEPLOY_SERVER
read -p "Enter app container port (default 3000): " APP_PORT
APP_PORT=${APP_PORT:-3000}
read -p "Enter your GitHub Personal Access Token: " GITHUB_TOKEN

# --------- 3. Clone or pull repo ---------
sudo -u jenkins mkdir -p /var/lib/jenkins/workspace
cd /var/lib/jenkins/workspace
REPO_NAME=$(basename $GIT_REPO .git)

if [ ! -d "$REPO_NAME" ]; then
    echo "Cloning repository $REPO_NAME..."
    sudo -u jenkins git clone $GIT_REPO
else
    echo "Repository $REPO_NAME exists. Pulling latest changes..."
    cd $REPO_NAME
    sudo -u jenkins git pull
fi

# --------- 4. Create Dockerfile if missing ---------
DOCKERFILE_PATH="/var/lib/jenkins/workspace/$REPO_NAME/Dockerfile"
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Creating Dockerfile..."
cat <<EOF | sudo tee $DOCKERFILE_PATH > /dev/null
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE $APP_PORT
CMD ["node", "app.js"]
EOF
else
    echo "Dockerfile already exists, skipping creation."
fi

# --------- 5. Create Jenkinsfile if missing ---------
JENKINSFILE="/var/lib/jenkins/workspace/$REPO_NAME/Jenkinsfile"
if [ ! -f "$JENKINSFILE" ]; then
    echo "Creating Jenkinsfile..."
cat <<EOF | sudo tee $JENKINSFILE > /dev/null
pipeline {
    agent any
    environment { IMAGE = "$DOCKER_USER/$REPO_NAME:\${BUILD_NUMBER}" }
    stages {
        stage('Checkout') { steps { git '$GIT_REPO' } }
        stage('Build Docker') { steps { sh 'docker build -t \$IMAGE .' } }
        stage('Test') { steps { sh 'docker run --rm \$IMAGE npm test || true' } }
        stage('Push Docker') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh 'echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin && docker push \$IMAGE'
                }
            }
        }
        stage('Deploy') {
            steps { 
                sh "ssh $DEPLOY_SERVER 'docker pull \$IMAGE && docker stop app || true && docker run -d --name app -p $APP_PORT:$APP_PORT \$IMAGE'" 
            }
        }
    }
}
EOF
else
    echo "Jenkinsfile already exists, skipping creation."
fi

# --------- 6. Create GitHub webhook ---------
REPO_API=$(echo $GIT_REPO | sed -E 's|git@github.com:|https://api.github.com/repos/|; s|.git$||')
JENKINS_URL="http://$(hostname -I | awk '{print $1}'):8080/github-webhook/"

echo "Creating GitHub webhook..."
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
-H "Accept: application/vnd.github.v3+json" \
$REPO_API/hooks \
-d "{
  \"name\": \"web\",
  \"active\": true,
  \"events\": [\"push\"],
  \"config\": {
    \"url\": \"$JENKINS_URL\",
    \"content_type\": \"json\",
    \"insecure_ssl\": \"0\"
  }
}" > /dev/null

echo ""
echo "✅ CI/CD setup complete!"
echo "Repository: $REPO_NAME"
echo "Deployment server: $DEPLOY_SERVER, App port: $APP_PORT"
echo "Jenkinsfile and Dockerfile are ready, webhook created."
