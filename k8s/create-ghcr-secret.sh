#!/bin/bash
# Script to create GitHub Container Registry (GHCR) pull secret for Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating GHCR Image Pull Secret${NC}"
echo ""

# Check if required tools are installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Get GitHub credentials
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -sp "Enter your GitHub Personal Access Token (PAT) with read:packages scope: " GITHUB_TOKEN
echo ""

# Namespace
NAMESPACE="demo"

echo -e "${YELLOW}Creating namespace ${NAMESPACE} if it doesn't exist...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo -e "${YELLOW}Creating image pull secret 'ghcr-creds' in namespace ${NAMESPACE}...${NC}"

# Delete existing secret if it exists
kubectl delete secret ghcr-creds -n ${NAMESPACE} --ignore-not-found=true

# Create the secret
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username="${GITHUB_USERNAME}" \
  --docker-password="${GITHUB_TOKEN}" \
  --docker-email="${GITHUB_USERNAME}@users.noreply.github.com" \
  --namespace=${NAMESPACE}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Secret 'ghcr-creds' created successfully in namespace ${NAMESPACE}${NC}"
else
    echo -e "${RED}✗ Failed to create secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Done! You can now deploy applications that use ghcr.io images.${NC}"
