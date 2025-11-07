#!/bin/bash
# Quick setup script for K8S-SLSA project
# This script helps configure the repository for your environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   K8S-SLSA Project Setup Script       ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check required tools
echo -e "${YELLOW}Checking required tools...${NC}"
MISSING_TOOLS=()

if ! command -v kubectl &> /dev/null; then
    MISSING_TOOLS+=("kubectl")
fi

if ! command -v docker &> /dev/null; then
    MISSING_TOOLS+=("docker")
fi

if ! command -v git &> /dev/null; then
    MISSING_TOOLS+=("git")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Missing required tools: ${MISSING_TOOLS[*]}${NC}"
    echo "Please install them before continuing."
    exit 1
fi

echo -e "${GREEN}✓ All required tools found${NC}"
echo ""

# Get GitHub username
echo -e "${YELLOW}Configuration:${NC}"
read -p "Enter your GitHub username: " GITHUB_USERNAME

if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}Error: GitHub username cannot be empty${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Updating configuration files...${NC}"

# Update CI/CD workflow
if [ -f ".github/workflows/ci.yml" ]; then
    sed -i.bak "s|ghcr.io/\${{ github.repository_owner }}/python-slsa-web|ghcr.io/${GITHUB_USERNAME}/python-slsa-web|g" .github/workflows/ci.yml
    echo -e "${GREEN}✓ Updated .github/workflows/ci.yml${NC}"
else
    echo -e "${RED}✗ .github/workflows/ci.yml not found${NC}"
fi

# Update deployment
if [ -f "k8s/deployment.yaml" ]; then
    sed -i.bak "s|ghcr.io/YOUR_USERNAME/python-slsa-web|ghcr.io/${GITHUB_USERNAME}/python-slsa-web|g" k8s/deployment.yaml
    echo -e "${GREEN}✓ Updated k8s/deployment.yaml${NC}"
else
    echo -e "${RED}✗ k8s/deployment.yaml not found${NC}"
fi

# Update Kyverno policy
if [ -f "kyverno/verify-image-signature.yaml" ]; then
    sed -i.bak "s|{{GITHUB_REPO_OWNER}}|${GITHUB_USERNAME}|g" kyverno/verify-image-signature.yaml
    sed -i.bak "s|{{GITHUB_REPO_NAME}}|K8S-SLSA|g" kyverno/verify-image-signature.yaml
    echo -e "${GREEN}✓ Updated kyverno/verify-image-signature.yaml${NC}"
else
    echo -e "${RED}✗ kyverno/verify-image-signature.yaml not found${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Configuration Complete!             ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Create Kubernetes namespace:"
echo "   ${BLUE}kubectl apply -f k8s/namespace.yaml${NC}"
echo ""
echo "2. Create GHCR image pull secret:"
echo "   ${BLUE}./k8s/create-ghcr-secret.sh${NC}"
echo ""
echo "3. Install Kyverno (optional but recommended):"
echo "   ${BLUE}helm repo add kyverno https://kyverno.github.io/kyverno/${NC}"
echo "   ${BLUE}helm install kyverno kyverno/kyverno -n kyverno --create-namespace${NC}"
echo "   ${BLUE}kubectl apply -f kyverno/${NC}"
echo ""
echo "4. Install Wazuh (optional):"
echo "   ${BLUE}helm repo add wazuh https://wazuh.github.io/wazuh-kubernetes${NC}"
echo "   ${BLUE}helm install wazuh wazuh/wazuh -n wazuh --create-namespace${NC}"
echo "   ${BLUE}# Then update wazuh/wazuh-agent-daemonset.yaml with your manager address${NC}"
echo "   ${BLUE}kubectl apply -f wazuh/${NC}"
echo ""
echo "5. Push to GitHub to trigger CI/CD:"
echo "   ${BLUE}git add .${NC}"
echo "   ${BLUE}git commit -m 'Configure for ${GITHUB_USERNAME}'${NC}"
echo "   ${BLUE}git push origin main${NC}"
echo ""
echo "6. Deploy application:"
echo "   ${BLUE}kubectl apply -f k8s/${NC}"
echo ""
echo -e "${GREEN}Happy deploying! 🚀${NC}"
echo ""
echo -e "${YELLOW}Note: Backup files (*.bak) were created. You can delete them with:${NC}"
echo "   ${BLUE}find . -name '*.bak' -delete${NC}"
