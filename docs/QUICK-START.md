# Quick Start Guide - SLSA L1 + L2

Get your SLSA L1+L2 pipeline running in **5 minutes**.

## ⚡ Prerequisites

- Self-hosted GitHub Actions runner (running)
- Docker installed on runner
- Kubernetes cluster with GHCR configured
- GitHub PAT with `packages:write` permission

## 🚀 Setup Steps

### 1. Clone and Configure (2 minutes)

```bash
# Clone your repo
git clone https://github.com/YOUR_USERNAME/K8S-SLSA.git
cd K8S-SLSA

# Update image name in workflow
sed -i 's/YOUR_USERNAME/YOUR_GITHUB_USERNAME/g' .github/workflows/slsa-l1-l2.yml

# Update deployment
sed -i 's/YOUR_USERNAME/YOUR_GITHUB_USERNAME/g' k8s/deployment.yaml
```

### 2. Create Kubernetes Resources (1 minute)

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create GHCR pull secret (if repo is private)
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_PAT \
  --namespace=demo
```

### 3. Trigger Build (1 minute)

```bash
# Commit and push
git add .
git commit -m "Configure SLSA L1+L2 pipeline"
git push origin main

# Watch the build
gh run watch
```

### 4. Deploy to Kubernetes (1 minute)

```bash
# Wait for CI to complete, then deploy
kubectl apply -f k8s/

# Verify
kubectl get pods -n demo
kubectl logs -n demo -l app=python-slsa-web -f
```

### 5. Test Access

```bash
# Port forward
kubectl port-forward -n demo svc/python-slsa-web 8080:80

# Test (in another terminal)
curl http://localhost:8080
# Should see: "Hello from secure CI/CD with SLSA + Cosign (Python Edition)!"
```

## ✅ Verify SLSA Compliance

### Check Provenance Exists

```bash
# Get your image name from CI output
IMAGE="ghcr.io/YOUR_USERNAME/python-slsa-web:latest"

# Inspect image
docker buildx imagetools inspect $IMAGE

# Look for:
# - MediaType: application/vnd.in-toto+json (SLSA provenance)
# - MediaType: application/vnd.in-toto+json (SBOM)
```

### Check GitHub Actions Ran It

```bash
# View workflow run
gh run list --workflow=slsa-l1-l2.yml

# View specific run details
gh run view <RUN_ID>

# Confirm:
# - Build ran on GitHub Actions (not manually)
# - Provenance was generated automatically
```

## 📊 What You've Achieved

- ✅ **SLSA Build L1**: Automated build with provenance
- ✅ **SLSA Build L2**: Hosted build platform (GitHub Actions)
- ✅ **Container Image**: Pushed to GHCR
- ✅ **SLSA Provenance**: Attached to image
- ✅ **SBOM**: Software Bill of Materials generated
- ✅ **Kubernetes Deployment**: Running in your cluster

## 🔍 Troubleshooting

### Pipeline Not Starting

```bash
# Check runner status
gh api repos/:owner/:repo/actions/runners

# On runner machine:
cd actions-runner
./run.sh  # Should show "Listening for Jobs"
```

### ImagePullBackOff

```bash
# Make image public (or fix secret)
# Go to: https://github.com/users/YOUR_USERNAME/packages/container/python-slsa-web/settings
# Change: Visibility → Public
```

### Provenance Not Showing

```bash
# Ensure workflow has provenance: true
grep "provenance:" .github/workflows/slsa-l1-l2.yml

# Ensure Docker Buildx is used
docker buildx version
```

## 📚 Next Steps

1. **Read SLSA-L1-L2-EXPLAINED.md** to understand what you just built
2. **Add Cosign signing** for image verification
3. **Add Wazuh** for security monitoring
4. **Add Kyverno** for policy enforcement
5. **Implement SLSA L3** with slsa-github-generator

## 🆘 Getting Help

- Check logs: `kubectl logs -n demo -l app=python-slsa-web`
- View CI logs: `gh run view <RUN_ID> --log`
- Check runner: `gh api repos/:owner/:repo/actions/runners`
- Read docs: `docs/SLSA-L1-L2-EXPLAINED.md`

---

**That's it! You now have SLSA L1+L2 working!** 🎉
