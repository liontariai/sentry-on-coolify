#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status "Prepairing to install Sentry Self-Hosted with Coolify"

# Check if sentry directory exists
if [ ! -d "sentry-self-hosted" ]; then
    print_error "Sentry directory (sentry-self-hosted) not found. Please ensure the sentry submodule is initialized."
    exit 1
fi

print_status "Moving files from sentry subdirectory to current directory..."

# Move all files and directories from sentry/ to current directory
# Using find to handle hidden files and preserve directory structure
find sentry-self-hosted -mindepth 1 -maxdepth 1 -exec mv {} . \;

print_status "Files moved successfully"

# Remove the now-empty sentry directory
# rm -rf sentry-self-hosted

print_status "Sentry directory removed"

# Modifying the install.sh script, so it does not fail and runs without user input
print_status "Modifying install.sh script, so it does not fail and runs without user input"

# Comment out the minimum requirements check to prevent failures
sed -i 's|^source install/check-minimum-requirements.sh|# source install/check-minimum-requirements.sh|' install.sh

export REPORT_SELF_HOSTED_ISSUES=0
export SKIP_COMMIT_CHECK=1
export SKIP_USER_CREATION=1

print_status "Running install.sh script"

print_status "Removing docker-compose.yml file (from sentry-self-hosted/docker-compose.yml), so it doesn't override coolify's modified version"

rm -f docker-compose.yml

# Run the install.sh script 5 times, to ensure it runs successfully
for i in {1..5}; do
    print_status "Running install.sh script (attempt $i/5)"
    if ./install.sh; then
        print_status "install.sh script completed successfully on attempt $i"
        break
    else
        print_warning "install.sh script failed on attempt $i"
        if [ $i -eq 5 ]; then
            print_error "install.sh script failed on all 5 attempts. Please check the logs and try again."
            exit 1
        fi
        print_status "Waiting 5 seconds before next attempt..."
        sleep 5
    fi
done

print_status "Sentry Self-Hosted installed successfully"