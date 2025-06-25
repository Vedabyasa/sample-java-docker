# Java Maven CI Pipeline (Local Bash Script)

This project provides a secure, production-ready shell-based pipeline to:

- Clone a Java Maven project from Git
- Build it using Maven
- Upload the artifact to Nexus
- Run SonarQube analysis
- Log all activity to timestamped files

---------

## Original Script Issues

The original script had several critical issues:

- Hardcoded secrets - Used `admin` credentials and token inline
- No error handling - Failures in Git, Maven, Nexus, or SonarQube weren’t caught
- No logging - No way to trace pipeline output or failures
- Incomplete validation - Didn’t check for required tools, folders, or files
- Poor SonarQube & Nexus integration - Didn’t verify if services were running, and upload was hardcoded/invalid
- No folder structure - Logs and outputs were messy

----------

## Improvements Made

- Parameterized inputs (Git repo, branch, project key, Nexus repo)
- `.env` support for credentials (no hardcoding)
- Error handling with proper logging
- Log files stored in `logs/` directory with timestamps
- Checking nexus & sonarQube if they are running and starting them if required
- Detecting Artifact and uploading that to Nexus
- SonarQube readiness check and scan
- Tool existence checks (`git`, `mvn`, `curl`, `docker`)
- `.gitignore` to avoid committing `.env` and logs

--------

## Pre-requisites

Ensure the following tools are installed:

- git
- java
- maven
- docker
- curl
- Local Nexus & SonarQube containers

## How to Run the Pipeline

### 1. Clone this repository

- Run `git clone https://github.com/Vedabyasa/sample-java-docker.git`

### 2. Setup .env file

- Create a file named .env with the following variables:

1. SONARQUBE_URL=http://localhost:9000
2. SONARQUBE_TOKEN=<sonar-token>
3. NEXUS_URL=http://localhost:8081
4. NEXUS_USERNAME=<nexus-username>
5. NEXUS_PASSWORD=<nexus-password>

- Load the .env file with the command `source .env`

### 3. Run the Pipeline

- chmod +x pipeline.sh
- ./pipeline.sh https://github.com/Vedabyasa/hello-world-maven.git main helloWorld raw-artifacts
- ./pipeline.sh https://github.com/spring-projects/spring-petclinic.git main petclinic raw-artifacts

## Logs

- All the logs will be saved to logs/pipeline_<timestamp>.log

## Output

- Artifacts are uploaded to the Nexus repository (e.g. raw-artifacts)
- SonarQube analysis is triggered and can be ssen in the dashboard
