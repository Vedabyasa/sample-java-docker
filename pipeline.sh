#!/bin/bash

set -euo pipefail

# Setting log file
LOG_FILE="pipeline_$(date +%F_%T).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# initializing logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Adding a check for command line arguments
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <GIT_REPOSITORY_url> <branch> <sonar_project_key> <nexus_repo>"
    log "Missing command line arguments - hence, pipeline failed..."
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

REPO_DIR=$(basename "$GIT_REPOSITORY" .git)

# Cloning the java repository from git
log "Cloning repository..."
rm -rf "$REPO_DIR"
git clone --branch "$BRANCH_NAME" "$GIT_REPOSITORY"
log "Git clone Successful"

cd "$REPO_DIR"

# Starting maven build
log "Building the project with Maven..."
mvn clean install

# Adding a check if the artifact created successfully
ARTIFACT_PATH=$(find target -name "*.jar" | head -n 1)
if [[ ! -f "$ARTIFACT_PATH" ]]; then
    log "Artifact not found!"
    exit 1
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
    log "❌ Failed to upload artifact to Nexus. HTTP status code: $UPLOAD_RESPONSE"
    exit 1
fi

# SonarQube Analysis
log "Running SonarQube analysis..."
log "SONAR_PROJECT_KEY: $SONAR_PROJECT_KEY"
mvn sonar:sonar \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.host.url="$SONARQUBE_URL" \
    -Dsonar.login="$SONARQUBE_TOKEN"

# Pipeline completes
log "✅ Pipeline completed successfully!"
