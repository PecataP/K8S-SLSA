# SLSA Level 3 Implementation Guide

This guide explains the complete SLSA L3 setup for this project, including slsa-github-generator, Cosign signing, and Kyverno policy enforcement.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [CI/CD Pipeline](#cicd-pipeline)
- [Kyverno Policies](#kyverno-policies)
- [Deployment Process](#deployment-process)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Overview

### What is SLSA L3?

SLSA (Supply-chain Levels for Software Artifacts) Level 3 provides:

- **Hardened Builds**: Builds run in isolated, ephemeral environments
- **Non-falsifiable Provenance**: Cryptographically signed build metadata that cannot be tampered with
- **Signature Verification**: Images are signed and verified before deployment
- **Policy Enforcement**: Automated checks ensure only compliant artifacts are deployed

### Our Implementation

```
┌─────────────────────────────────────────────────────────────┐
│              GitHub Actions (Self-hosted Runner)             │
│                                                              │
│  1. Build container image (Docker Buildx)                   │
│  2. Push to GHCR                                            │
│  3. Sign with Cosign (keyless OIDC)                         │
│  4. Generate SLSA L3 provenance (slsa-github-generator)     │
│                                                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Image + Signature + Provenance
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    GHCR (Container Registry)                 │
│                                                              │
│  - Image layers (sha256 digest)                             │
│  - Cosign signature (OCI artifact)                          │
│  - SLSA provenance attestation (OCI artifact)               │
│  - SBOM (OCI artifact)                                      │
│                                                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Pull (digest reference)
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│                                                              │
│  ┌────────────────────────────────────────────┐            │
│  │      Kyverno Admission Controller           │            │
│  │                                             │            │
│  │  1. Check digest (not tag)                 │            │
│  │  2. Verify Cosign signature                │            │
│  │  3. Verify SLSA L3 provenance              │            │
│  │                                             │            │
│  │  ✅ All checks pass → Deploy pod            │            │
│  │  ❌ Any check fails → Block deployment      │            │
│  └────────────────────────────────────────────┘            │
│                       │                                      │
│                       ▼                                      │
│              ┌─────────────────┐                            │
│              │  Running Pods   │                            │
│              │  (Verified)     │                            │
│              └─────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### On Your Self-hosted Runner

```bash
# Install Cosign
wget https://github.com/sigstore/cosign/releases/download/v2.2.3/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign
cosign version

# Install slsa-verifier (optional, for manual verification)
wget https://github.com/slsa-framework/slsa-verifier/releases/download/v2.5.1/slsa-verifier-linux-amd64
sudo mv slsa-verifier-linux-amd64 /usr/local/bin/slsa-verifier
sudo chmod +x /usr/local/bin/slsa-verifier
slsa-verifier version
```

### In Your Kubernetes Cluster

```bash
# Install Kyverno
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml

# Verify Kyverno is running
kubectl get pods -n kyverno

# Expected output:
# kyverno-admission-controller-xxx   Running
# kyverno-background-controller-xxx  Running
# kyverno-cleanup-controller-xxx     Running
# kyverno-reports-controller-xxx     Running
```

## Installation

### Step 1: Apply Kyverno Policies

```bash
# Apply all SLSA L3 policies
kubectl apply -f k8s/kyverno-policies/

# Verify policies are installed
kubectl get clusterpolicies

# Expected output:
# NAME                       BACKGROUND   VALIDATE ACTION   READY
# require-image-digest       true         Enforce           True
# verify-image-signature     false        Enforce           True
# verify-slsa-provenance     false        Enforce           True
```

### Step 2: Review Policy Configuration

The policies are in **Enforce** mode by default. If you want to test first without blocking:

```bash
# Switch to Audit mode (logs violations but doesn't block)
kubectl patch clusterpolicy require-image-digest --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
kubectl patch clusterpolicy verify-slsa-provenance --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'

# View policy violations
kubectl get policyreport -n demo
```

## CI/CD Pipeline

### Workflow: `.github/workflows/slsa-l3.yml`

The pipeline has 4 main jobs:

#### 1. **build-and-push**
- Builds container image with Docker Buildx
- Pushes to GHCR
- Signs image with Cosign (keyless OIDC)
- Outputs image digest for next jobs

#### 2. **provenance**
- Uses `slsa-github-generator` to generate L3 provenance
- Runs in isolated environment (hardened build)
- Provenance is cryptographically signed
- Attached to image as OCI attestation

#### 3. **verify**
- Verifies Cosign signature
- Verifies SLSA L3 provenance with slsa-verifier
- Ensures everything is correct before deployment

#### 4. **summary**
- Generates GitHub Actions summary
- Provides deployment commands
- Shows verification commands

### Key Features

**Keyless Signing with Cosign:**
- No private keys to manage
- Uses GitHub Actions OIDC identity
- Signatures logged in Rekor transparency log
- Tied to specific workflow and repository

**SLSA L3 Provenance:**
- Generated by `slsa-github-generator` (not user-controlled)
- Contains build parameters, materials, builder identity
- Non-falsifiable (cryptographically signed by the generator)
- Meets all SLSA L3 requirements

## Kyverno Policies

### 1. Require Image Digest

**File**: `k8s/kyverno-policies/require-image-digest.yaml`

Forces all images to use digest references:
- ✅ `ghcr.io/pecatap/python-slsa-web@sha256:abc123...`
- ❌ `ghcr.io/pecatap/python-slsa-web:latest`
- ❌ `ghcr.io/pecatap/python-slsa-web:v1.0`

**Why**: Tags are mutable and can be overwritten (tag mutation attack). Digests are immutable.

### 2. Verify Image Signature

**File**: `k8s/kyverno-policies/verify-image-signature.yaml`

Verifies Cosign signatures:
- Checks that image is signed with Cosign
- Uses keyless verification (OIDC)
- Ensures signature is from authorized GitHub workflow
- Verifies signature against Rekor transparency log

### 3. Verify SLSA L3 Provenance

**File**: `k8s/kyverno-policies/verify-slsa-provenance.yaml`

Verifies SLSA provenance:
- Checks for SLSA provenance attestation
- Verifies provenance is signed by slsa-github-generator
- Validates builder identity and build type
- Ensures L3 requirements are met

## Deployment Process

### Automatic Workflow

1. **Push code** to main branch
2. **GitHub Actions** builds and signs image
3. **Get the digest** from GitHub Actions output
4. **Update deployment** with new digest
5. **Apply to cluster** - Kyverno verifies automatically

### Manual Steps

#### Option 1: Using Helper Script (Recommended)

```bash
# Get digest from GitHub Actions
DIGEST=$(gh run view --log | grep "Digest:" | awk '{print $2}')

# Update and deploy
./scripts/update-deployment-digest.sh "${DIGEST}"
```

The script will:
- Update `k8s/deployment.yaml` with new digest
- Show you the changes
- Ask for confirmation
- Apply to cluster
- Wait for rollout to complete

#### Option 2: Manual Update

```bash
# Get the digest from GitHub Actions output
DIGEST="sha256:abc123def456..."

# Update deployment.yaml
# Change: image: ghcr.io/pecatap/python-slsa-web@sha256:OLD
# To:     image: ghcr.io/pecatap/python-slsa-web@sha256:NEW

# Apply
kubectl apply -f k8s/deployment.yaml

# Watch rollout
kubectl rollout status deployment/python-slsa-web -n demo
```

#### Option 3: kubectl set image

```bash
DIGEST="sha256:abc123def456..."

kubectl set image deployment/python-slsa-web \
  python-slsa-web=ghcr.io/pecatap/python-slsa-web@${DIGEST} \
  -n demo
```

## Verification

### View Kyverno Admission Logs

```bash
# Watch admission decisions in real-time
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller -f

# You should see:
# - Image digest verification: PASS
# - Signature verification: PASS
# - Provenance verification: PASS
```

### Verify Signature Locally

```bash
# Get running image
IMAGE=$(kubectl get pod -n demo -l app=python-slsa-web -o jsonpath='{.items[0].spec.containers[0].image}')

# Verify Cosign signature
cosign verify \
  --certificate-identity-regexp='https://github.com/PecataP/K8S-SLSA/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  ${IMAGE}
```

### Verify SLSA L3 Provenance Locally

```bash
# Get running image
IMAGE=$(kubectl get pod -n demo -l app=python-slsa-web -o jsonpath='{.items[0].spec.containers[0].image}')

# Verify provenance
slsa-verifier verify-image \
  --source-uri github.com/PecataP/K8S-SLSA \
  --source-branch main \
  ${IMAGE}
```

### View All Attestations

```bash
# See everything attached to the image
cosign tree ghcr.io/pecatap/python-slsa-web:latest

# Output shows:
# - Image manifest
# - Signature
# - SLSA provenance
# - SBOM
```

## Troubleshooting

### Issue: Pod creation blocked by Kyverno

**Symptom**:
```
Error: admission webhook denied the request: policy verify-image-signature failed
```

**Debug**:
```bash
# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=100

# Check policy status
kubectl get clusterpolicy verify-image-signature -o yaml

# View policy reports
kubectl get policyreport -n demo -o yaml
```

**Common causes**:
1. Image not signed → Run CI pipeline
2. Using tag instead of digest → Use `@sha256:...`
3. Wrong OIDC identity in policy → Check workflow path
4. Network issues reaching Rekor → Check connectivity

### Issue: Signature verification fails

**Symptom**:
```
Error: no matching signatures
```

**Solutions**:

1. **Check if image is signed**:
   ```bash
   cosign tree ghcr.io/pecatap/python-slsa-web@sha256:...
   # Should show signatures
   ```

2. **Verify OIDC identity**:
   ```bash
   # Get signature details
   cosign verify ghcr.io/pecatap/python-slsa-web@sha256:... 2>&1 | grep certificate

   # Should match policy:
   # subject: https://github.com/PecataP/K8S-SLSA/.github/workflows/slsa-l3.yml@refs/heads/main
   # issuer: https://token.actions.githubusercontent.com
   ```

3. **Check Rekor transparency log**:
   ```bash
   rekor-cli search --artifact ghcr.io/pecatap/python-slsa-web@sha256:...
   ```

### Issue: Provenance verification fails

**Symptom**:
```
Error: SLSA provenance verification failed
```

**Debug**:
```bash
# Check if provenance exists
cosign tree ghcr.io/pecatap/python-slsa-web@sha256:...

# Download provenance
cosign download attestation ghcr.io/pecatap/python-slsa-web@sha256:... | jq .

# Check builder ID
cosign download attestation ghcr.io/pecatap/python-slsa-web@sha256:... | jq -r '.payload' | base64 -d | jq '.predicate.builder.id'
# Should be: https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.0.0
```

### Issue: Webhook timeout

**Symptom**:
```
Error: context deadline exceeded
```

**Solution**: Increase timeout in policy:
```yaml
spec:
  webhookTimeoutSeconds: 60  # Increase from 30
```

### Issue: First build after enabling policies

The first time you enable policies, you need an image that passes verification:

```bash
# Option 1: Switch policies to Audit mode temporarily
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
kubectl patch clusterpolicy verify-slsa-provenance --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'

# Run CI pipeline to build and sign image
gh workflow run slsa-l3.yml

# Wait for completion, then update deployment with digest
# Then switch back to Enforce mode
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
kubectl patch clusterpolicy verify-slsa-provenance --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
```

## Testing

### Test 1: Unsigned Image (Should Fail)

```bash
kubectl run test-unsigned --image=nginx:latest -n demo

# Expected: Blocked by verify-image-signature policy
```

### Test 2: Tag Instead of Digest (Should Fail)

```bash
kubectl run test-tag --image=ghcr.io/pecatap/python-slsa-web:latest -n demo

# Expected: Blocked by require-image-digest policy
```

### Test 3: Valid SLSA L3 Image (Should Succeed)

```bash
kubectl apply -f k8s/deployment.yaml

# Expected: Pod created successfully
# Kyverno verifies digest, signature, and provenance
```

## SLSA L3 Compliance Checklist

- [x] **Scripted build**: Fully automated in GitHub Actions
- [x] **Provenance exists**: Generated by slsa-github-generator
- [x] **Hosted build**: GitHub Actions (not local)
- [x] **Provenance authenticity**: Generated by build service
- [x] **Hardened builds**: slsa-github-generator provides isolation
- [x] **Non-falsifiable provenance**: Cryptographically signed by generator
- [x] **Image signing**: Cosign with keyless OIDC
- [x] **Digest references**: Kubernetes manifests use `@sha256:...`
- [x] **Policy enforcement**: Kyverno verifies before admission
- [x] **Transparency logging**: Signatures in Rekor

## What's Next?

### SLSA Level 4

For L4, you would need:
- **Two-person review**: Require code review before merge
- **Hermetic builds**: Fully isolated builds with no network access
- **Build as code**: Explicitly defined build process
- **Ephemeral environments**: Fresh build environment each time

### Additional Security

- **Image scanning**: Integrate Trivy or similar
- **Runtime security**: Add Falco or similar
- **Network policies**: Restrict pod communication
- **Secrets management**: Use sealed secrets or external secrets
- **Monitoring**: Set up alerts for policy violations

## Resources

- [SLSA Specification](https://slsa.dev/)
- [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator)
- [Cosign Documentation](https://docs.sigstore.dev/cosign/overview/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [Sigstore Documentation](https://docs.sigstore.dev/)

## Support

For issues:
1. Check Kyverno logs: `kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller`
2. Check policy reports: `kubectl get policyreport -n demo -o yaml`
3. Verify image locally with cosign and slsa-verifier
4. Review GitHub Actions logs for build failures
