# ArgoCD GitOps Integration

This document explains how ArgoCD is integrated with the SLSA L1/L2 pipeline for continuous deployment.

## Overview

**ArgoCD** provides GitOps-based continuous deployment, automatically syncing your Kubernetes cluster with the `k8s/` manifests in this repository.

**Integration Flow**:
```
GitHub Actions (CI)           ArgoCD (CD)
    └─> Build image      ────>  └─> Deploy to cluster
    └─> Generate SLSA           └─> Auto-sync from git
    └─> Push to GHCR            └─> Health monitoring
```

## Architecture

```
┌─────────────────┐
│  Git Repository │
│   (k8s/*.yaml)  │
└────────┬────────┘
         │
         │ Watches for changes
         ▼
┌─────────────────┐
│     ArgoCD      │
│  (argocd ns)    │
└────────┬────────┘
         │
         │ Applies manifests
         ▼
┌─────────────────┐
│  Kubernetes     │
│  (demo ns)      │
└─────────────────┘
```

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- ArgoCD namespace created: `argocd`
- This repository accessible to ArgoCD

## Setup

### 1. Verify ArgoCD Installation

```bash
# Check ArgoCD is running
kubectl get pods -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 2. Deploy the Application

```bash
# Apply the ArgoCD Application manifest
kubectl apply -f argocd/application.yaml

# Verify application is created
kubectl get application python-slsa-web -n argocd
```

### 3. Initial Sync

```bash
# Trigger initial sync (if not auto-synced)
kubectl -n argocd patch application python-slsa-web \
  --type merge \
  --patch '{"operation": {"sync": {}}}'

# Or use ArgoCD CLI
argocd app sync python-slsa-web
```

### 4. Monitor Deployment

```bash
# Watch application status
kubectl get application python-slsa-web -n argocd -w

# Check deployed resources
kubectl get all -n demo

# View sync status
argocd app get python-slsa-web
```

## Application Configuration

The ArgoCD Application is defined in `argocd/application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: python-slsa-web
  namespace: argocd
spec:
  # Source: Your Git repository
  source:
    repoURL: https://github.com/PecataP/K8S-SLSA.git
    targetRevision: main
    path: k8s

  # Destination: Where to deploy
  destination:
    server: https://kubernetes.default.svc
    namespace: demo

  # Sync Policy: Automatic
  syncPolicy:
    automated:
      prune: true      # Remove deleted resources
      selfHeal: true   # Auto-fix drift
```

### Key Features

| Feature | Setting | Description |
|---------|---------|-------------|
| **Auto-sync** | `automated: true` | Automatically deploys when git changes |
| **Prune** | `prune: true` | Removes resources deleted from git |
| **Self-heal** | `selfHeal: true` | Reverts manual changes to match git |
| **Create Namespace** | `CreateNamespace: true` | Auto-creates `demo` namespace |

## GitOps Workflow

### Development Workflow

1. **Build phase** (GitHub Actions):
   ```bash
   git push origin main
   # → Triggers .github/workflows/slsa-l1-l2.yml
   # → Builds image with SLSA provenance
   # → Pushes to ghcr.io/pecatap/python-slsa-web:latest
   ```

2. **Update manifests**:
   ```bash
   # Update deployment with new image digest
   kubectl set image deployment/python-slsa-web \
     python-slsa-web=ghcr.io/pecatap/python-slsa-web@sha256:abc123... \
     -n demo --dry-run=client -o yaml > k8s/deployment.yaml

   # Commit the change
   git add k8s/deployment.yaml
   git commit -m "Update image to sha256:abc123..."
   git push
   ```

3. **ArgoCD auto-deploys**:
   ```
   ArgoCD detects git change
   → Syncs new deployment manifest
   → Kubernetes rolls out new pods
   → Health checks verify deployment
   ```

### Monitoring Deployments

```bash
# ArgoCD UI (recommended)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: http://localhost:8080
# Login: admin / <password from step 1>

# CLI - Application status
argocd app get python-slsa-web

# CLI - Sync history
argocd app history python-slsa-web

# Kubernetes - Pod status
kubectl get pods -n demo -w
kubectl logs -n demo -l app=python-slsa-web -f
```

## Common Operations

### Manual Sync

```bash
# Sync now (if auto-sync is disabled)
argocd app sync python-slsa-web

# Sync with prune
argocd app sync python-slsa-web --prune

# Hard refresh (ignore cache)
argocd app sync python-slsa-web --force
```

### View Differences

```bash
# See what will change on next sync
argocd app diff python-slsa-web

# Compare live vs git
kubectl get deployment python-slsa-web -n demo -o yaml > /tmp/live.yaml
diff /tmp/live.yaml k8s/deployment.yaml
```

### Rollback

```bash
# View history
argocd app history python-slsa-web

# Rollback to previous revision
argocd app rollback python-slsa-web <revision-id>

# Or use Kubernetes
kubectl rollout undo deployment/python-slsa-web -n demo
```

### Pause Auto-Sync

```bash
# Disable auto-sync temporarily
kubectl patch application python-slsa-web -n argocd \
  --type merge \
  --patch '{"spec": {"syncPolicy": {"automated": null}}}'

# Re-enable auto-sync
kubectl patch application python-slsa-web -n argocd \
  --type merge \
  --patch '{"spec": {"syncPolicy": {"automated": {"prune": true, "selfHeal": true}}}}'
```

## Troubleshooting

### Application Not Syncing

**Check sync status**:
```bash
kubectl describe application python-slsa-web -n argocd
argocd app get python-slsa-web
```

**Common issues**:
- Git repository not accessible (check repo URL)
- Invalid manifests in `k8s/` (check YAML syntax)
- Namespace doesn't exist (check `CreateNamespace` option)

### Out of Sync State

**Cause**: Manual changes to cluster resources

**Solution**:
```bash
# Let ArgoCD auto-heal (if selfHeal is enabled)
# Or manually sync
argocd app sync python-slsa-web

# To allow manual changes, disable selfHeal:
kubectl patch application python-slsa-web -n argocd \
  --type merge \
  --patch '{"spec": {"syncPolicy": {"automated": {"selfHeal": false}}}}'
```

### Health Check Failures

**Check application health**:
```bash
argocd app get python-slsa-web
kubectl get pods -n demo
kubectl describe pod <pod-name> -n demo
```

**Common issues**:
- ImagePullBackOff (check GHCR credentials)
- CrashLoopBackOff (check application logs)
- Readiness probe failing (check probe configuration)

### Image Pull Errors

If pods can't pull from GHCR:

```bash
# Create image pull secret (if repository is private)
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_GITHUB_PAT \
  -n demo

# Add to deployment (already configured in k8s/deployment.yaml)
imagePullSecrets:
  - name: ghcr-creds
```

## Security Considerations

### SLSA + ArgoCD Integration

ArgoCD deployment maintains SLSA compliance:

| SLSA Requirement | Implementation | Status |
|------------------|----------------|--------|
| **Provenance** | Generated by GitHub Actions | Yes |
| **Attestation** | Attached to GHCR image | Yes |
| **GitOps** | All changes via git commits | Yes |
| **Auditability** | Git history + ArgoCD sync history | Yes |

### Best Practices

1. **Use image digests** (not tags) in production:
   ```yaml
   image: ghcr.io/pecatap/python-slsa-web@sha256:abc123...
   # Instead of: ghcr.io/pecatap/python-slsa-web:latest
   ```

2. **Enable RBAC** for ArgoCD:
   ```bash
   # Restrict who can sync applications
   kubectl edit configmap argocd-rbac-cm -n argocd
   ```

3. **Monitor sync failures**:
   ```bash
   # Set up alerts for failed syncs
   kubectl get application -n argocd -o json | \
     jq '.items[] | select(.status.sync.status != "Synced")'
   ```

4. **Use private repositories** for sensitive configurations:
   ```bash
   # Add private repo credentials
   argocd repo add https://github.com/user/private-repo \
     --username <username> \
     --password <token>
   ```

## Integration with CI/CD

### Current State

**Manual image update**:
1. CI builds and pushes image
2. You manually update `k8s/deployment.yaml` with new digest
3. ArgoCD auto-syncs the change

### Future Enhancement: ArgoCD Image Updater

To fully automate, you can install ArgoCD Image Updater:

```bash
# Install Image Updater
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Configure application for auto-update
kubectl annotate application python-slsa-web -n argocd \
  argocd-image-updater.argoproj.io/image-list=python-slsa-web=ghcr.io/pecatap/python-slsa-web \
  argocd-image-updater.argoproj.io/python-slsa-web.update-strategy=digest
```

This will:
- Monitor GHCR for new image digests
- Automatically update `k8s/deployment.yaml`
- Commit changes back to git
- Trigger ArgoCD sync

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/)
- [GitOps Principles](https://opengitops.dev/)

## Quick Reference

```bash
# Application status
argocd app get python-slsa-web

# Sync application
argocd app sync python-slsa-web

# View logs
argocd app logs python-slsa-web

# Delete application (removes from ArgoCD, not cluster)
argocd app delete python-slsa-web

# View resources
kubectl get all -n demo

# Access application
kubectl port-forward -n demo svc/python-slsa-web 8080:80
```

## Next Steps

1. **Current**: Manual image updates + ArgoCD auto-sync
2. **Future**: Add ArgoCD Image Updater for full automation
3. **Future**: Add Kyverno policies to verify SLSA provenance before deployment
4. **Future**: Integrate with Wazuh for security monitoring
