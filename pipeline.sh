#!/bin/bash

set -euo pipefail

# Setting log file
mkdir -p logs
LOG_FILE="logs/pipeline_$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# initializing logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Common function to check if services are ready
wait_for_service() {
  local name="$1"
  local url="$2"
  local check_string="$3"
  log "Waiting for $name to be ready..."
  for i in {1..30}; do
    if curl -s "$url" | grep -q "$check_string"; then
      log "✅ $name is ready."
      return 0
    fi
    log "Waiting for $name... ($i/30)"
    sleep 5
  done
  log "❌ $name did not become ready in time - hence, stopping the execution..."
  return 1
}

# Adding a check for command line arguments
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <GIT_REPOSITORY_url> <branch> <sonar_project_key> <nexus_repo>"
    log "Missing command line arguments - hence, stopping the execution..."
    exit 1
fi

# Getting all the parameters from command line argument
GIT_REPOSITORY="$1"
BRANCH_NAME="$2"
SONAR_PROJECT_KEY="$3"
NEXUS_REPOSITORY="$4"

# Adding a check for all the env variables
: "${SONARQUBE_URL:?Need to set SONARQUBE_URL}"
: "${SONARQUBE_TOKEN:?Need to set SONARQUBE_TOKEN}"
: "${NEXUS_URL:?Need to set NEXUS_URL}"
: "${NEXUS_USERNAME:?Need to set NEXUS_USERNAME}"
: "${NEXUS_PASSWORD:?Need to set NEXUS_PASSWORD}"

# Checking if all the require commands are installed
for cmd in git mvn curl docker; do
  if ! command -v $cmd &> /dev/null; then
    log "❌ Required command '$cmd' is not installed - hence, stopping the execution..."
    exit 1
  fi
done

REPO_DIR=$(basename "$GIT_REPOSITORY" .git)

# Cloning the java repository from git
log "Cloning repository..."
rm -rf "$REPO_DIR"
if git clone --branch "$BRANCH_NAME" "$GIT_REPOSITORY"; then
  log "✅ Git clone successful."
else
  log "❌ Git clone failed. Please check the repository URL or branch - stopping the execution..."
  exit 1
fi

cd "$REPO_DIR"

# checking for valid maven project
if [[ ! -f "pom.xml" ]]; then
  log "❌ No pom.xml found. Not a Maven project - hence, stopping the execution..."
  exit 1
fi

# Starting maven build
log "Building the project with Maven..."
if mvn clean install; then
  log "✅ Maven build successful."
else
  log "❌ Maven build failed - hence, stopping the execution..."
  exit 1
fi

# Adding a check if the artifact created successfully
ARTIFACT_PATH=$(find target -name "*.jar" | head -n 1)
if [[ ! -f "$ARTIFACT_PATH" ]]; then
    log "Artifact not found - hence, stopping the execution..."
    exit 1
fi

log "Found artifact: $ARTIFACT_PATH"

# Check if Nexus is running on the expected port
log "Checking if Nexus is running..."
if ! curl -s --head --request GET "${NEXUS_URL}" | grep "200 OK" > /dev/null; then
    log "Nexus is not responding at $NEXUS_URL"

    # Attempt to start the Nexus Docker container
    if docker ps -a --format '{{.Names}}' | grep -q "^nexus$"; then
        log "Starting Nexus container..."
        docker start nexus
        wait_for_service "Nexus" "${NEXUS_URL}/service/rest/v1/status" '"status":"STARTED"' || exit 1
    else
        log "❌ Nexus container not found. Please run or install Nexus manually - hence, stopping the execution..."
        exit 1
    fi
else
    log "✅ Nexus is running at $NEXUS_URL"
fi

# Uploading artifcats to Nexus
log "Uploading artifact to Nexus..."
UPLOAD_URL="${NEXUS_URL}/repository/${NEXUS_REPOSITORY}/$(basename "$ARTIFACT_PATH")"
log "Uploading to Nexus URL: $UPLOAD_URL"

UPLOAD_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
  --upload-file "$ARTIFACT_PATH" "$UPLOAD_URL")

# Checking if nexus upload is succcessful
if [[ "$UPLOAD_RESPONSE" == "201" ]]; then
    log "✅ Artifact uploaded successfully to Nexus."
else
    log "❌ Failed to upload artifact to Nexus. HTTP status code: $UPLOAD_RESPONSE - hence, stopping the execution..."
    exit 1
fi
# Checking if sonarQube is running, else starting
log "Checking if SonarQube is running..."
if ! curl -s --head --request GET "${SONARQUBE_URL}" | grep "200 OK" > /dev/null; then
  log "SonarQube is not responding at $SONARQUBE_URL"

  if docker ps -a --format '{{.Names}}' | grep -q "^sonarqube$"; then
    log "Starting SonarQube container..."
    docker start sonarqube
    wait_for_service "SonarQube" "${SONARQUBE_URL}/api/system/status" '"status":"UP"' || exit 1
  else
    log "❌ SonarQube container not found. Please install or run SonarQube manually - hence, stopping the execution..."
    exit 1
  fi
else
  log "✅ SonarQube is running at $SONARQUBE_URL"
fi

# SonarQube Analysis
log "Running SonarQube analysis..."
mvn sonar:sonar \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.host.url="$SONARQUBE_URL" \
    -Dsonar.login="$SONARQUBE_TOKEN"

# Pipeline completes
log "✅ Pipeline completed successfully!"
