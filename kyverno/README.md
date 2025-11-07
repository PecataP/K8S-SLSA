# Kyverno Policy Configuration

This directory contains Kyverno policies for enforcing security and supply chain best practices.

## Policies Included

1. **verify-image-signature.yaml** - Verifies Cosign signatures on container images
2. **require-security-context.yaml** - Enforces restrictive security contexts
3. **restrict-image-registries.yaml** - Restricts images to approved registries only

## Installation

### Install Kyverno

```bash
# Install Kyverno using Helm
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Or using kubectl
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.0/install.yaml
```

### Apply Policies

Before applying the policies, update the GitHub repository references in `verify-image-signature.yaml`:

```bash
# Replace placeholders with your actual values
sed -i 's/{{GITHUB_REPO_OWNER}}/your-username/g' verify-image-signature.yaml
sed -i 's/{{GITHUB_REPO_NAME}}/K8S-SLSA/g' verify-image-signature.yaml

# Apply all policies
kubectl apply -f verify-image-signature.yaml
kubectl apply -f require-security-context.yaml
kubectl apply -f restrict-image-registries.yaml
```

## Testing Policies

### Start in Audit Mode

For testing, change `validationFailureAction: Enforce` to `Audit` in each policy. This will log violations without blocking deployments:

```bash
# Check policy violations
kubectl get policyreport -A
kubectl describe policyreport -n demo
```

### Switch to Enforce Mode

Once you've verified the policies work correctly, change back to `Enforce`:

```bash
kubectl edit clusterpolicy verify-image-signature
# Change validationFailureAction: Audit to Enforce
```

## Verifying Image Signatures

To manually verify an image signature:

```bash
# Get the image digest
IMAGE="ghcr.io/your-username/python-slsa-web:latest"
DIGEST=$(crane digest $IMAGE)

# Verify with Cosign
cosign verify $IMAGE@$DIGEST \
  --certificate-identity-regexp="https://github.com/your-username/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"

# Verify SLSA provenance
cosign verify-attestation $IMAGE@$DIGEST \
  --type slsaprovenance \
  --certificate-identity-regexp="https://github.com/your-username/K8S-SLSA" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

## Troubleshooting

### Image signature verification fails

- Ensure the image was built and signed by the CI pipeline
- Check that the OIDC issuer and subject match your repository
- Verify Rekor transparency log is accessible: https://rekor.sigstore.dev

### Pods stuck in pending state

- Check policy reports: `kubectl get policyreport -A`
- View Kyverno logs: `kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno`
- Temporarily set policies to Audit mode to diagnose issues
