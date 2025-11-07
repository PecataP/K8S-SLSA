# Getting Started with K8S-SLSA

This guide will walk you through setting up and deploying your Python application with full SLSA security compliance, Cosign signing, Kyverno policies, and Wazuh monitoring.

## 📋 Prerequisites Checklist

Before you begin, ensure you have:

- [ ] Kubernetes cluster (Minikube, Kind, or cloud provider)
- [ ] `kubectl` installed and configured
- [ ] `docker` installed (for local testing)
- [ ] `helm` installed (v3.0+)
- [ ] GitHub account with Actions enabled
- [ ] Git installed

## 🚀 Quick Start (5 minutes)

### Step 1: Run Setup Script

```bash
# Make sure you're in the repository root
cd K8S-SLSA

# Run the automated setup script
./setup.sh
```

This script will:
- Check for required tools
- Prompt for your GitHub username
- Update all configuration files automatically
- Show you the next steps

### Step 2: Create Kubernetes Resources

```bash
# Create the demo namespace
kubectl apply -f k8s/namespace.yaml

# Create GHCR image pull secret
./k8s/create-ghcr-secret.sh
```

### Step 3: Install Kyverno (Policy Engine)

```bash
# Add Kyverno Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=300s

# Apply policies (start in Audit mode for testing)
kubectl apply -f kyverno/
```

### Step 4: Trigger CI/CD Pipeline

```bash
# Commit and push to trigger the pipeline
git add .
git commit -m "Initial setup and configuration"
git push origin main

# Watch the GitHub Actions workflow
# Visit: https://github.com/YOUR_USERNAME/K8S-SLSA/actions
```

### Step 5: Deploy Application

After the CI pipeline completes successfully:

```bash
# Deploy the application
kubectl apply -f k8s/

# Watch the deployment
kubectl get pods -n demo -w

# Check deployment status
kubectl get all -n demo
```

### Step 6: Access Your Application

```bash
# Get the node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Access the application
curl http://$NODE_IP:30080

# Or use port-forward
kubectl port-forward -n demo svc/python-slsa-web 8080:80
curl http://localhost:8080
```

## 📊 Understanding SLSA Levels

Your pipeline now implements all three SLSA levels:

### SLSA Level 1: Automated Build ✅
- Fully automated GitHub Actions workflow
- No manual intervention required
- Reproducible builds

### SLSA Level 2: Build Service ✅
- GitHub Actions as trusted build platform
- Automated SLSA provenance generation
- Provenance cryptographically signed

### SLSA Level 3: Hardened Builds ✅
- Isolated, ephemeral build environments
- Keyless signing with OIDC (no long-lived secrets)
- Build integrity recorded in Rekor transparency log

## 🔒 Security Features Explained

### 1. Cosign Image Signing

Every container image is signed using Sigstore Cosign:

```bash
# Verify the signature of your image
cosign verify ghcr.io/YOUR_USERNAME/python-slsa-web:latest \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

**What this means**:
- Only images built by your GitHub Actions can run
- Tampering is detected automatically
- No secrets to manage (keyless signing)

### 2. Kyverno Policy Enforcement

Kyverno acts as a gatekeeper for your cluster:

```bash
# View policy reports
kubectl get clusterpolicy
kubectl get policyreport -A

# See what Kyverno is blocking/auditing
kubectl describe policyreport -n demo
```

**Policies in place**:
- ✅ Only signed images are allowed
- ✅ Images must have SLSA provenance
- ✅ Containers must run as non-root
- ✅ Read-only root filesystem enforced
- ✅ All capabilities dropped
- ✅ Only approved registries allowed

### 3. SLSA Provenance

Each build generates cryptographic proof of how it was built:

```bash
# Verify SLSA provenance
cosign verify-attestation ghcr.io/YOUR_USERNAME/python-slsa-web:latest \
  --type slsaprovenance \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

**What's included**:
- Source code commit SHA
- Build parameters
- Builder identity
- Dependencies used
- Build timestamp

## 🔍 Optional: Install Wazuh for Security Monitoring

Wazuh provides runtime security monitoring, vulnerability detection, and compliance checking.

### Quick Install

```bash
# Install Wazuh Manager and Dashboard
helm repo add wazuh https://wazuh.github.io/wazuh-kubernetes
helm install wazuh wazuh/wazuh -n wazuh --create-namespace

# Wait for Wazuh to be ready (this may take 5-10 minutes)
kubectl wait --for=condition=ready pod -l app=wazuh-manager -n wazuh --timeout=600s

# Get the Wazuh Manager IP
WAZUH_MANAGER_IP=$(kubectl get svc -n wazuh wazuh-manager -o jsonpath='{.spec.clusterIP}')

# Update the agent configuration
sed -i "s/wazuh-manager.wazuh.svc.cluster.local/${WAZUH_MANAGER_IP}/g" wazuh/wazuh-agent-daemonset.yaml

# Deploy Wazuh agents
kubectl apply -f wazuh/wazuh-rbac.yaml
kubectl apply -f wazuh/wazuh-agent-config.yaml
kubectl apply -f wazuh/wazuh-agent-daemonset.yaml

# Access Wazuh Dashboard
kubectl port-forward -n wazuh svc/wazuh-dashboard 443:443
# Visit: https://localhost:443 (admin/admin)
```

### What Wazuh Monitors

- 🔍 File integrity changes
- 🐛 Vulnerabilities (CVEs) in containers
- 📋 CIS Kubernetes and Docker compliance
- 🚨 Security events and anomalies
- 📊 System inventory and process monitoring

## 🧪 Testing the Security

### Test 1: Try to Deploy Unsigned Image

```bash
# This should be blocked by Kyverno
kubectl run test-unsigned --image=nginx:latest -n demo

# Check why it was blocked
kubectl get events -n demo | grep -i blocked
```

### Test 2: Verify Image Signature

```bash
# This should succeed
cosign verify ghcr.io/YOUR_USERNAME/python-slsa-web:latest \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

### Test 3: Check SLSA Provenance

```bash
# View the provenance
cosign verify-attestation ghcr.io/YOUR_USERNAME/python-slsa-web:latest \
  --type slsaprovenance \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" | jq .
```

### Test 4: Try to Run as Root (Should Fail)

Edit `k8s/deployment.yaml` and try to add:
```yaml
securityContext:
  runAsUser: 0  # root
```

Apply and watch Kyverno block it:
```bash
kubectl apply -f k8s/deployment.yaml
# Should see error about security policy violation
```

## 📈 Monitoring and Observability

### View Application Logs

```bash
# Follow logs in real-time
kubectl logs -n demo -l app=python-slsa-web -f

# View logs from specific pod
kubectl logs -n demo <POD_NAME>
```

### Check Policy Compliance

```bash
# View all policy reports
kubectl get policyreport -A

# Detailed report for demo namespace
kubectl describe policyreport -n demo

# View Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
```

### Monitor with Wazuh (if installed)

```bash
# View Wazuh agent status
kubectl get pods -n wazuh

# Check agent logs
kubectl logs -n wazuh -l app=wazuh-agent

# Access dashboard for detailed monitoring
kubectl port-forward -n wazuh svc/wazuh-dashboard 443:443
```

## 🐛 Troubleshooting

### Issue: Pods stuck in ImagePullBackOff

**Solution**:
```bash
# Check if secret exists
kubectl get secret ghcr-creds -n demo

# Recreate if needed
./k8s/create-ghcr-secret.sh

# Make image public (alternative)
# Go to: https://github.com/users/YOUR_USERNAME/packages/container/python-slsa-web/settings
# Change visibility to public
```

### Issue: Kyverno blocks deployment

**Solution**:
```bash
# Check what's being blocked
kubectl describe pod -n demo

# Temporarily switch to Audit mode
kubectl edit clusterpolicy verify-image-signature
# Change: validationFailureAction: Audit

# Check policy reports
kubectl get policyreport -n demo -o yaml
```

### Issue: CI pipeline fails at signing

**Solution**:
- Check that `id-token: write` permission is in workflow
- Verify repository has Actions enabled
- Check GitHub Actions logs for specific error
- Ensure Rekor (rekor.sigstore.dev) is accessible

### Issue: SLSA provenance generation fails

**Solution**:
- Verify `actions: read` permission is set
- Check that image digest is properly passed between jobs
- Review slsa-github-generator logs
- Ensure repository is not a fork (some features limited)

## 📚 Next Steps

Now that you have a secure pipeline running, consider:

1. **Add More Applications**: Use this as a template for other services
2. **Network Policies**: Add Kubernetes NetworkPolicies for network segmentation
3. **Secrets Management**: Integrate with HashiCorp Vault or sealed-secrets
4. **Observability**: Add Prometheus and Grafana for metrics
5. **GitOps**: Integrate with ArgoCD or Flux for GitOps deployments
6. **Multiple Environments**: Create dev/staging/prod namespaces
7. **Custom Policies**: Add more Kyverno policies specific to your needs

## 📖 Learning Resources

- [SLSA Documentation](https://slsa.dev/) - Deep dive into SLSA levels
- [Cosign Documentation](https://docs.sigstore.dev/cosign/overview/) - Learn keyless signing
- [Kyverno Policies](https://kyverno.io/policies/) - Browse policy examples
- [Wazuh Use Cases](https://documentation.wazuh.com/current/getting-started/use-cases/) - Security monitoring scenarios
- [Kubernetes Security](https://kubernetes.io/docs/concepts/security/) - K8s security best practices

## 🤝 Getting Help

- **Issues**: [GitHub Issues](https://github.com/YOUR_USERNAME/K8S-SLSA/issues)
- **Discussions**: [GitHub Discussions](https://github.com/YOUR_USERNAME/K8S-SLSA/discussions)
- **Documentation**: Check README.md and CLAUDE.md

## ✅ Success Checklist

You know you're successful when:

- [ ] CI pipeline completes all jobs (build, sign, provenance)
- [ ] Image is signed and signature verifies
- [ ] SLSA provenance is attached and verifies
- [ ] Kyverno policies are enforced (or auditing)
- [ ] Application deploys successfully to K8s
- [ ] Application is accessible via service
- [ ] Wazuh agents are monitoring (if installed)
- [ ] Policy reports show compliance
- [ ] No security context violations

Congratulations! You now have a production-ready secure deployment pipeline! 🎉
