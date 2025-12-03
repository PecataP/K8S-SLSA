#!/bin/bash
# Update Kubernetes deployment with new image digest
# This script helps you update the deployment after a CI build

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="ghcr.io/pecatap/python-slsa-web"
DEPLOYMENT_FILE="k8s/deployment.yaml"
NAMESPACE="demo"

echo -e "${BLUE}=== SLSA L3 Deployment Digest Updater ===${NC}"
echo

# Check if digest is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Image digest not provided${NC}"
    echo
    echo "Usage: $0 <digest>"
    echo "Example: $0 sha256:abc123def456..."
    echo
    echo "To get the latest digest from GitHub Actions:"
    echo "  gh run view --log | grep 'Digest:'"
    echo
    exit 1
fi

DIGEST="$1"

# Validate digest format
if [[ ! "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    echo -e "${RED}Error: Invalid digest format${NC}"
    echo "Digest must be in format: sha256:<64-hex-characters>"
    echo "Got: $DIGEST"
    exit 1
fi

FULL_IMAGE="${IMAGE_NAME}@${DIGEST}"

echo -e "${GREEN}✓${NC} Image: ${IMAGE_NAME}"
echo -e "${GREEN}✓${NC} Digest: ${DIGEST}"
echo -e "${GREEN}✓${NC} Full reference: ${FULL_IMAGE}"
echo

# Update the deployment file
echo -e "${BLUE}Updating deployment file...${NC}"

# Create backup
cp "${DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}.backup"
echo -e "${GREEN}✓${NC} Backup created: ${DEPLOYMENT_FILE}.backup"

# Update the image reference
sed -i "s|image: ${IMAGE_NAME}@sha256:[a-f0-9]*|image: ${FULL_IMAGE}|g" "${DEPLOYMENT_FILE}"
sed -i "s|image: ${IMAGE_NAME}:.*|image: ${FULL_IMAGE}|g" "${DEPLOYMENT_FILE}"

echo -e "${GREEN}✓${NC} Deployment file updated"
echo

# Show the diff
echo -e "${BLUE}Changes made:${NC}"
diff -u "${DEPLOYMENT_FILE}.backup" "${DEPLOYMENT_FILE}" || true
echo

# Ask for confirmation before applying
read -p "Apply this deployment to cluster? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Applying deployment...${NC}"
    kubectl apply -f "${DEPLOYMENT_FILE}"

    echo -e "${GREEN}✓${NC} Deployment applied"
    echo

    # Wait for rollout
    echo -e "${BLUE}Waiting for rollout to complete...${NC}"
    kubectl rollout status deployment/python-slsa-web -n "${NAMESPACE}" --timeout=300s

    echo
    echo -e "${GREEN}✓${NC} Deployment successful!"
    echo

    # Show pod status
    echo -e "${BLUE}Pod status:${NC}"
    kubectl get pods -n "${NAMESPACE}" -l app=python-slsa-web

else
    echo -e "${BLUE}Deployment not applied. File updated but not applied to cluster.${NC}"
    echo "To apply manually, run: kubectl apply -f ${DEPLOYMENT_FILE}"
fi

echo
echo -e "${BLUE}=== Verification Commands ===${NC}"
echo
echo "Verify image signature:"
echo "  cosign verify \\"
echo "    --certificate-identity-regexp='https://github.com/PecataP/K8S-SLSA/.*' \\"
echo "    --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \\"
echo "    ${FULL_IMAGE}"
echo
echo "Verify SLSA L3 provenance:"
echo "  slsa-verifier verify-image \\"
echo "    --source-uri github.com/PecataP/K8S-SLSA \\"
echo "    ${FULL_IMAGE}"
echo
