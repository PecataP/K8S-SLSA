# Kubernetes SLSA Level 3 Secure Pipeline

[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)

A production-ready implementation of **SLSA Level 3** (Supply-chain Levels for Software Artifacts) with Kubernetes deployment, featuring cryptographic signing, non-falsifiable provenance, and policy-based verification.

## Project Overview

This project demonstrates a complete SLSA Level 3 secure software supply chain:

- ✅ **SLSA L3 Provenance**: Non-falsifiable build provenance via `slsa-github-generator`
- ✅ **Image Signing**: Keyless signing with Cosign (Sigstore)
- ✅ **Digest-based Deployment**: Immutable image references
- ✅ **Policy Enforcement**: Kyverno policies for automated verification
- ✅ **Transparency**: All signatures logged in Rekor public ledger

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions (CI/CD)                     │
│  1. Build container image                                   │
│  2. Sign with Cosign (keyless OIDC)                         │
│  3. Generate SLSA L3 provenance (slsa-github-generator)     │
│  4. Verify signatures and provenance                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              GHCR (GitHub Container Registry)                │
│  - Image (with digest)                                      │
│  - Cosign signature                                         │
│  - SLSA L3 provenance                                       │
│  - SBOM                                                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster + Kyverno                    │
│  ┌───────────────────────────────────────────┐             │
│  │  Admission Control                         │             │
│  │  1. Require digest (not tags)             │             │
│  │  2. Verify Cosign signature                │             │
│  │  3. Verify SLSA L3 provenance             │             │
│  │  4. Block non-compliant images             │             │
│  └───────────────────────────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│              ✅ Verified Pod Deployed                         │
└─────────────────────────────────────────────────────────────┘
```

## What is SLSA Level 3?

SLSA L3 provides the highest level of supply chain security before requiring two-person review:

| Level | Requirement | How We Achieve It |
|-------|-------------|-------------------|
| **L1** | Provenance exists | ✅ SLSA provenance generated |
| **L1** | Scripted build | ✅ GitHub Actions workflow |
| **L2** | Hosted build platform | ✅ GitHub Actions (not local) |
| **L2** | Service-generated provenance | ✅ Build service creates provenance |
| **L3** | Hardened builds | ✅ slsa-github-generator (isolated) |
| **L3** | Non-falsifiable provenance | ✅ Generator signs (user can't modify) |
| **L3** | Build isolation | ✅ Ephemeral build environments |

## Prerequisites

### On Your Self-hosted Runner

```bash
# Install Cosign for signing
wget https://github.com/sigstore/cosign/releases/download/v2.2.3/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign
cosign version

# Install slsa-verifier for verification
wget https://github.com/slsa-framework/slsa-verifier/releases/download/v2.5.1/slsa-verifier-linux-amd64
sudo mv slsa-verifier-linux-amd64 /usr/local/bin/slsa-verifier
sudo chmod +x /usr/local/bin/slsa-verifier
slsa-verifier version
```

### In Your Kubernetes Cluster

```bash
# Install Kyverno
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml

# Verify installation
kubectl get pods -n kyverno

# Apply SLSA L3 policies
kubectl apply -f k8s/kyverno-policies/

# Verify policies
kubectl get clusterpolicies
```

## Quick Start

### 1. First Build

Trigger the SLSA L3 pipeline:

```bash
git push origin main
```

Watch the workflow:
```bash
gh run watch
```

The workflow will:
1. Build the container image
2. Sign it with Cosign (keyless)
3. Generate SLSA L3 provenance
4. Verify everything

### 2. Get the Image Digest

After the build completes:

```bash
# Get the digest from the latest run
DIGEST=$(gh run view --log | grep "Digest:" | head -1 | awk '{print $NF}')
echo $DIGEST
```

### 3. Update Deployment

Use the helper script:

```bash
./scripts/update-deployment-digest.sh "${DIGEST}"
```

Or manually update `k8s/deployment.yaml`:
```yaml
image: ghcr.io/pecatap/python-slsa-web@sha256:YOUR_DIGEST_HERE
```

### 4. Deploy to Kubernetes

```bash
# Apply deployment
kubectl apply -f k8s/deployment.yaml

# Kyverno will automatically verify:
# ✅ Image uses digest (not tag)
# ✅ Image is signed with Cosign
# ✅ Image has SLSA L3 provenance

# Check deployment
kubectl get pods -n demo
kubectl logs -n demo -l app=python-slsa-web
```

### 5. Access the Application

```bash
# Port forward
kubectl port-forward -n demo svc/python-slsa-web 8080:80

# Test
curl http://localhost:8080
```

## Verification

### Verify Image Signature

```bash
# Get the image reference
IMAGE=$(kubectl get deployment python-slsa-web -n demo -o jsonpath='{.spec.template.spec.containers[0].image}')

# Verify with Cosign
cosign verify \
  --certificate-identity-regexp='https://github.com/PecataP/K8S-SLSA/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  ${IMAGE}
```

Expected output:
```
Verification for ghcr.io/pecatap/python-slsa-web@sha256:...
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
```

### Verify SLSA L3 Provenance

```bash
# Verify with slsa-verifier
slsa-verifier verify-image \
  --source-uri github.com/PecataP/K8S-SLSA \
  --source-branch main \
  ${IMAGE}
```

Expected output:
```
Verified signature against tlog entry index...
Verified build using builder "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.0.0"
Verifying artifact ghcr.io/pecatap/python-slsa-web@sha256:...
PASSED: Verified SLSA provenance
```

### View All Attestations

```bash
# See everything attached to the image
cosign tree ghcr.io/pecatap/python-slsa-web:latest
```

Output shows:
- 📦 Image manifest
- ✍️ Cosign signature
- 📜 SLSA provenance attestation
- 📋 SBOM

## How It Works

### 1. Build Phase (GitHub Actions)

The `.github/workflows/slsa-l3.yml` workflow:

```yaml
jobs:
  build-and-push:
    # Builds image, signs with Cosign
    - docker build → push to GHCR
    - cosign sign --yes (keyless OIDC)

  provenance:
    # Generates L3 provenance (YOU don't control this)
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v2.0.0

  verify:
    # Verifies everything worked
    - cosign verify
    - slsa-verifier verify-image
```

**Key Point**: The provenance is generated by `slsa-github-generator`, not your workflow. This makes it **non-falsifiable** (L3 requirement).

### 2. Signing with Cosign (Keyless)

No private keys needed! We use **OIDC keyless signing**:

1. GitHub Actions generates an OIDC token
2. Token contains your workflow identity: `https://github.com/PecataP/K8S-SLSA/.github/workflows/slsa-l3.yml@refs/heads/main`
3. Cosign uses this identity to sign
4. Signature logged in Rekor transparency log
5. Anyone can verify using the OIDC issuer and identity

### 3. SLSA L3 Provenance

The provenance contains:

```json
{
  "builder": {
    "id": "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.0.0"
  },
  "buildType": "https://slsa.dev/container-based-build/v0.1",
  "invocation": {
    "configSource": {
      "repository": "https://github.com/PecataP/K8S-SLSA",
      "ref": "refs/heads/main",
      "commit": "sha256:abc123..."
    }
  },
  "materials": [
    {"uri": "git+https://github.com/PecataP/K8S-SLSA@abc123..."},
    {"uri": "pkg:docker/python@3.11-alpine"}
  ]
}
```

This proves:
- **What** was built (your code + dependencies)
- **Where** it was built (GitHub Actions)
- **How** it was built (slsa-github-generator)
- **When** it was built (timestamp)

### 4. Kyverno Policy Enforcement

Three ClusterPolicies enforce SLSA L3:

#### Policy 1: Require Image Digest
```yaml
# Blocks: ghcr.io/pecatap/python-slsa-web:latest ❌
# Allows: ghcr.io/pecatap/python-slsa-web@sha256:abc123 ✅
```

#### Policy 2: Verify Image Signature
```yaml
# Checks:
# - Image is signed with Cosign
# - Signature is from your authorized workflow
# - Signature exists in Rekor log
```

#### Policy 3: Verify SLSA L3 Provenance
```yaml
# Checks:
# - Provenance attestation exists
# - Signed by slsa-github-generator (not user)
# - Builder ID matches expected
# - Build type is container-based
```

If any policy fails, pod creation is **blocked**.

## Repository Structure

```
K8S-SLSA/
├── .github/workflows/
│   ├── slsa-l3.yml                    # Main SLSA L3 CI/CD pipeline
│   ├── build-base-image.yml           # Custom base image builder
│   └── slsa-l1-l2.yml.disabled        # Old L1/L2 workflow (reference)
│
├── app/
│   ├── app.py                         # Python web application
│   └── requirements.txt               # Python dependencies
│
├── k8s/
│   ├── deployment.yaml                # Kubernetes deployment (uses digest)
│   ├── service.yaml                   # Kubernetes service
│   ├── namespace.yaml                 # Demo namespace
│   └── kyverno-policies/              # SLSA L3 enforcement policies
│       ├── require-image-digest.yaml
│       ├── verify-image-signature.yaml
│       └── verify-slsa-provenance.yaml
│
├── scripts/
│   └── update-deployment-digest.sh    # Helper to update deployment
│
├── base-image/
│   └── Dockerfile                     # Custom Python base image
│
├── DOCKERFILE                         # Application Dockerfile
├── DOCKERFILE.base                    # Base image Dockerfile
└── README.md                          # This file
```

## CI/CD Pipeline Details

### Job 1: Build and Push

1. Checkout code
2. Set up Docker Buildx
3. Login to GHCR
4. Build image
5. Push to GHCR (get digest)
6. **Install Cosign**
7. **Sign image with keyless OIDC**

### Job 2: Provenance

1. Receives digest from Job 1
2. Calls `slsa-github-generator` (reusable workflow)
3. Generator runs in **isolated environment**
4. Generator creates **non-falsifiable provenance**
5. Generator signs and attaches provenance to image

### Job 3: Verify

1. Install verification tools
2. **Verify Cosign signature**
   - Checks identity matches workflow
   - Checks signature in Rekor
3. **Verify SLSA L3 provenance**
   - Checks provenance exists
   - Checks signed by generator
   - Validates build metadata
4. Display all attestations

### Job 4: Summary

1. Generates GitHub Actions summary
2. Shows SLSA compliance status
3. Provides deployment commands
4. Shows verification commands

## Security Features

### 🔐 Cryptographic Signing
Every image is signed with Cosign using keyless OIDC. No private keys to manage or protect.

### 🛡️ Non-falsifiable Provenance
Provenance generated by `slsa-github-generator` in an isolated environment that you don't control.

### 🔒 Immutable References
Deployments use digests (`@sha256:...`) which are cryptographically bound to image content.

### ✅ Automated Verification
Kyverno policies automatically verify every deployment. No manual checks needed.

### 📋 Transparency
All signatures logged in Rekor public transparency log. Fully auditable.

### 🚫 Attack Prevention

**What this protects against:**
- ✅ Compromised dependencies
- ✅ Malicious code injection
- ✅ Build process tampering
- ✅ Image substitution attacks
- ✅ Tag mutation attacks
- ✅ Unauthorized deployments

**What this doesn't protect against:**
- ❌ Vulnerabilities in your code (use scanning)
- ❌ Runtime attacks (use runtime security)
- ❌ Zero-day exploits (need monitoring)

## Troubleshooting

### Issue: Kyverno blocks my deployment

**Check which policy failed:**
```bash
kubectl get policyreport -n demo -o yaml
```

**Common causes:**
1. Using tag instead of digest → Update to use `@sha256:...`
2. Image not signed → Run CI pipeline to sign
3. Wrong OIDC identity → Check workflow path in policy

**Temporary workaround (testing only):**
```bash
# Switch to Audit mode (logs but doesn't block)
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
```

### Issue: Cosign verification fails

**Check if image is signed:**
```bash
cosign tree ghcr.io/pecatap/python-slsa-web@sha256:YOUR_DIGEST
```

**Verify OIDC identity:**
```bash
cosign verify ghcr.io/pecatap/python-slsa-web@sha256:YOUR_DIGEST 2>&1 | grep certificate
```

Should match:
- `certificate-identity`: `https://github.com/PecataP/K8S-SLSA/.github/workflows/slsa-l3.yml@refs/heads/main`
- `certificate-oidc-issuer`: `https://token.actions.githubusercontent.com`

### Issue: Provenance verification fails

**Check builder ID:**
```bash
cosign download attestation ghcr.io/pecatap/python-slsa-web@sha256:YOUR_DIGEST | \
  jq -r '.payload' | base64 -d | jq '.predicate.builder.id'
```

Should be: `https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.0.0`

### Issue: First deployment after enabling policies

**Solution**: Build a signed image first

```bash
# 1. Switch policies to Audit mode temporarily
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
kubectl patch clusterpolicy verify-slsa-provenance --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'

# 2. Run CI pipeline
gh workflow run slsa-l3.yml

# 3. Wait for completion and update deployment

# 4. Switch back to Enforce mode
kubectl patch clusterpolicy verify-image-signature --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
kubectl patch clusterpolicy verify-slsa-provenance --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
```

## Monitoring

### View Kyverno Logs

```bash
# Admission controller logs (real-time verification)
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller -f

# Policy reports
kubectl get policyreport -A
```

### View GitHub Actions Logs

```bash
# List recent runs
gh run list --workflow=slsa-l3.yml

# View specific run
gh run view RUN_ID --log
```

### View Rekor Transparency Log

```bash
# Search for your image signatures
rekor-cli search --artifact ghcr.io/pecatap/python-slsa-web@sha256:YOUR_DIGEST
```

## Best Practices

1. **Always use digests** in production deployments
2. **Never bypass Kyverno** policies in production
3. **Monitor policy violations** regularly
4. **Rotate base images** monthly for security updates
5. **Review provenance** before deploying to production
6. **Audit Rekor logs** for unexpected signatures
7. **Keep Kyverno updated** for latest security features

## Upgrading to SLSA L4

For even higher security, SLSA L4 requires:

- ✅ Two-person review (branch protection + required reviews)
- ✅ Hermetic builds (fully isolated, no network)
- ✅ Build as code (explicitly defined build process)
- ✅ Ephemeral environments (fresh environment each build)

Most of these can be achieved with:
- GitHub branch protection rules
- GitHub Actions environment protection
- Hermetic build tools (like Bazel)

## Resources

- [SLSA Specification](https://slsa.dev/)
- [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator)
- [Cosign Documentation](https://docs.sigstore.dev/cosign/overview/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [Sigstore Project](https://www.sigstore.dev/)

## Contributing

Contributions welcome! Please:

1. Test changes in a non-production environment
2. Ensure all policies pass
3. Verify signatures and provenance
4. Update documentation

## License

MIT License - See LICENSE file for details

## Security

For security issues, please see [SECURITY.md](SECURITY.md) for responsible disclosure process.

---

**Built with SLSA Level 3 compliance** 🔒

This project demonstrates production-ready supply chain security using industry best practices and open-source tools.
