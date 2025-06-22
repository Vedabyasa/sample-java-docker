#!/bin/bash

set -euo pipefail

LOG_FILE="pipeline_$(date +%F_%T).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <git_repo_url> <branch> <sonar_project_key> <nexus_repo>"
    exit 1
fi

GIT_REPO="$1"
BRANCH="$2"
SONAR_PROJECT_KEY="$3"
NEXUS_REPO="$4"

: "${SONARQUBE_URL:?Need to set SONARQUBE_URL}"
: "${SONARQUBE_TOKEN:?Need to set SONARQUBE_TOKEN}"
: "${NEXUS_URL:?Need to set NEXUS_URL}"
: "${NEXUS_USERNAME:?Need to set NEXUS_USERNAME}"
: "${NEXUS_PASSWORD:?Need to set NEXUS_PASSWORD}"

REPO_DIR=$(basename "$GIT_REPO" .git)

log "Cloning repository..."
rm -rf "$REPO_DIR"
git clone --branch "$BRANCH" "$GIT_REPO"
cd "$REPO_DIR"

log "Building the project with Maven..."
mvn clean install

ARTIFACT_PATH=$(find target -name "*.jar" | head -n 1)
if [[ ! -f "$ARTIFACT_PATH" ]]; then
    log "Artifact not found!"
    exit 1
fi

log "Uploading artifact to Nexus..."
UPLOAD_URL="${NEXUS_URL}/repository/${NEXUS_REPO}/$(basename "$ARTIFACT_PATH")"
log "Uploading to Nexus URL: $UPLOAD_URL"
curl -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" --upload-file "$ARTIFACT_PATH" "$UPLOAD_URL"

log "Running SonarQube analysis..."
mvn sonar:sonar \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.host.url="$SONARQUBE_URL" \
    -Dsonar.login="$SONARQUBE_TOKEN"

log "✅ Pipeline completed successfully!"
