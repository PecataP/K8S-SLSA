# Kubernetes SLSA Security Pipeline

A production-ready Kubernetes deployment with comprehensive supply chain security implementing SLSA (Supply-chain Levels for Software Artifacts) Levels 1, 2, and 3, along with Cosign image signing, Kyverno policy enforcement, and Wazuh security monitoring.

## 🎯 Project Overview

This project demonstrates modern DevSecOps practices by deploying a simple Python web application with enterprise-grade security controls:

- **SLSA Level 1, 2, & 3**: Full supply chain security compliance
- **Cosign Signing**: Keyless container image signing with Sigstore
- **Kyverno**: Policy-based admission control and image verification
- **Wazuh**: Real-time security monitoring and threat detection
- **Kubernetes**: Hardened deployment with security best practices

## 📋 Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Security Features](#security-features)
- [SLSA Compliance](#slsa-compliance)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI/CD                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Build   │→ │   SLSA   │→ │  Cosign  │→ │  Deploy  │   │
│  │  Image   │  │Provenance│  │   Sign   │  │   to K8s │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│               Kubernetes Cluster                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    Kyverno                            │  │
│  │  • Verify Image Signatures                           │  │
│  │  • Check SLSA Provenance                             │  │
│  │  • Enforce Security Policies                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │             Python Web Application                    │  │
│  │  • Non-root user                                     │  │
│  │  • Read-only filesystem                              │  │
│  │  • Capabilities dropped                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↓                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                Wazuh Agents                           │  │
│  │  • File Integrity Monitoring                         │  │
│  │  • Vulnerability Detection                           │  │
│  │  • Compliance Checking (CIS)                         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Prerequisites

### Required Tools

- **Kubernetes Cluster** (v1.24+)
  - Minikube, Kind, or any cloud provider (GKE, EKS, AKS)
- **kubectl** (v1.24+)
- **Docker** (v20.10+)
- **Git**
- **GitHub Account** with Actions enabled

### Optional Tools

- **Helm** (v3.0+) - For Kyverno and Wazuh installation
- **Cosign** (v2.0+) - For local image verification
- **crane** - For image digest inspection

### GitHub Secrets Required

1. `KUBE_CONFIG` - Base64-encoded kubeconfig for deployment (optional)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/K8S-SLSA.git
cd K8S-SLSA
```

### 2. Update Configuration

Edit `.github/workflows/ci.yml` and replace:
- `YOUR_USERNAME` with your GitHub username

Edit `k8s/deployment.yaml` and replace:
- `YOUR_USERNAME` with your GitHub username

Edit `kyverno/verify-image-signature.yaml` and replace:
- `{{GITHUB_REPO_OWNER}}` with your GitHub username
- `{{GITHUB_REPO_NAME}}` with `K8S-SLSA`

### 3. Set Up Kubernetes Cluster

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create GHCR image pull secret
./k8s/create-ghcr-secret.sh
```

### 4. Install Kyverno

```bash
# Install Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Apply policies (after updating placeholders)
kubectl apply -f kyverno/
```

### 5. Install Wazuh (Optional)

```bash
# Deploy Wazuh manager (or use external)
helm repo add wazuh https://wazuh.github.io/wazuh-kubernetes
helm install wazuh wazuh/wazuh -n wazuh --create-namespace

# Deploy Wazuh agents
kubectl apply -f wazuh/wazuh-rbac.yaml
kubectl apply -f wazuh/wazuh-agent-config.yaml
kubectl apply -f wazuh/wazuh-agent-daemonset.yaml
```

### 6. Trigger CI/CD Pipeline

```bash
# Push to main branch to trigger build
git add .
git commit -m "Initial setup"
git push origin main

# Or manually trigger workflow
gh workflow run ci.yml
```

### 7. Deploy Application

```bash
# Deploy the application
kubectl apply -f k8s/

# Verify deployment
kubectl get pods -n demo
kubectl get svc -n demo
```

### 8. Access Application

```bash
# Get node IP
kubectl get nodes -o wide

# Access application
curl http://<NODE_IP>:30080
```

## 🔒 Security Features

### 1. SLSA Compliance

| Level | Requirements | Implementation |
|-------|-------------|----------------|
| **L1** | Automated build process | ✅ GitHub Actions workflow |
| **L2** | Build service with provenance | ✅ slsa-github-generator |
| **L3** | Hardened build platform | ✅ Isolated runners, provenance verification |

### 2. Image Signing with Cosign

- **Keyless Signing**: No long-lived secrets using OIDC
- **Transparency Log**: All signatures recorded in Rekor
- **Verification**: Automated verification in Kubernetes with Kyverno

```bash
# Verify image signature manually
cosign verify ghcr.io/YOUR_USERNAME/python-slsa-web:latest \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

### 3. Kyverno Policy Enforcement

- **Image Verification**: Only signed images allowed
- **Security Context**: Enforce non-root, read-only filesystem
- **Registry Restriction**: Only approved registries

### 4. Wazuh Security Monitoring

- **File Integrity Monitoring**: Track changes to critical files
- **Vulnerability Detection**: Scan for CVEs
- **CIS Benchmarks**: Kubernetes and Docker compliance
- **Container Security**: Monitor Docker/containerd events

### 5. Kubernetes Security Hardening

- Non-root user (UID 1000)
- Read-only root filesystem
- No privilege escalation
- Dropped capabilities
- Resource limits
- Seccomp profile

## 📊 SLSA Compliance

### SLSA Level 1: Automated Build

✅ **Automated Build Process**
- GitHub Actions workflow
- Reproducible builds
- Version control integration

### SLSA Level 2: Build Service

✅ **Provenance Generation**
- Automated provenance creation
- Signed provenance attestation
- Provenance includes build parameters

✅ **Build Service**
- GitHub Actions as build service
- Hosted build environment
- Build logs retained

### SLSA Level 3: Hardened Builds

✅ **Isolated Builds**
- Ephemeral build environments
- No persistent credentials
- Build hermiticity

✅ **Provenance Verification**
- Cryptographic verification
- Transparency log (Rekor)
- OIDC-based authentication

## 📦 Deployment

### Manual Deployment

```bash
# Deploy all components
kubectl apply -f k8s/

# Check status
kubectl get all -n demo

# View logs
kubectl logs -n demo -l app=python-slsa-web -f

# Access service
kubectl port-forward -n demo svc/python-slsa-web 8080:80
curl http://localhost:8080
```

### Automated Deployment

The CI/CD pipeline includes an optional deployment job that runs on manual workflow trigger:

```bash
gh workflow run ci.yml
```

Ensure `KUBE_CONFIG` secret is set in GitHub repository secrets.

## 📈 Monitoring

### Application Logs

```bash
# View application logs
kubectl logs -n demo -l app=python-slsa-web -f

# View all events
kubectl get events -n demo
```

### Kyverno Policy Reports

```bash
# View policy violations
kubectl get policyreport -A

# Detailed report
kubectl describe policyreport -n demo
```

### Wazuh Dashboard

```bash
# Port forward to Wazuh dashboard
kubectl port-forward -n wazuh svc/wazuh-dashboard 443:443

# Access at: https://localhost:443
# Default: admin / admin (change immediately)
```

### Security Events

Wazuh monitors and alerts on:
- Unsigned image deployment attempts
- Policy violations
- File integrity changes
- Vulnerability detections
- CIS benchmark failures

## 🔍 Troubleshooting

### Image Pull Errors

```bash
# Verify secret exists
kubectl get secret ghcr-creds -n demo

# Recreate secret if needed
./k8s/create-ghcr-secret.sh
```

### Kyverno Policy Blocks Deployment

```bash
# Check policy violations
kubectl describe pod <POD_NAME> -n demo

# Temporarily set to Audit mode
kubectl edit clusterpolicy verify-image-signature
# Change: validationFailureAction: Audit
```

### Wazuh Agent Not Connecting

```bash
# Check agent logs
kubectl logs -n wazuh -l app=wazuh-agent

# Verify manager address in DaemonSet
kubectl edit daemonset wazuh-agent -n wazuh
```

### CI/CD Pipeline Failures

Common issues:
1. **SLSA provenance fails**: Check permissions in workflow
2. **Cosign signing fails**: Verify `id-token: write` permission
3. **Image push fails**: Check GHCR permissions

## 🏗️ Development

### Local Testing

```bash
# Build image locally
docker build -t python-slsa-web:dev .

# Run container
docker run -p 8080:8080 python-slsa-web:dev

# Test
curl http://localhost:8080
```

### Running Python App Directly

```bash
cd app
python3 app.py
```

## 📚 Additional Resources

- [SLSA Framework](https://slsa.dev/)
- [Sigstore Cosign](https://docs.sigstore.dev/cosign/overview/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔐 Security

For security issues, please see [SECURITY.md](SECURITY.md) for our vulnerability disclosure policy.

## 👥 Authors

- Your Name - Initial work

## 🙏 Acknowledgments

- SLSA Framework team
- Sigstore project
- Kyverno community
- Wazuh team
- Kubernetes security community
