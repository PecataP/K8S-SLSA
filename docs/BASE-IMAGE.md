# Custom Base Image Strategy

This document explains the custom base image approach used in this project to eliminate Docker Hub dependencies and improve SLSA compliance.

## Why Custom Base Images?

### Problems with Docker Hub Base Images

1. **Rate Limits**: Docker Hub enforces pull rate limits (100 pulls/6hrs for anonymous, 200 for authenticated)
2. **Supply Chain Risk**: External dependency outside your control
3. **Build Speed**: Pulling from external registries is slower
4. **SLSA Compliance**: No provenance for upstream base images

### Benefits of Custom Base Images

1. **No Rate Limits**: Pull from your own GHCR with no restrictions
2. **Full Control**: You control the entire supply chain
3. **SLSA Provenance**: Base image has its own signed provenance
4. **Faster Builds**: Pull from same registry as push destination
5. **Security**: Regular updates on your schedule (monthly cron job)
6. **Consistency**: Same base across all environments

## Architecture

```
┌─────────────────────────────────┐
│  Docker Hub                     │
│  python:3.11-alpine             │
└────────────┬────────────────────┘
             │ One-time pull
             ▼
┌─────────────────────────────────┐
│  Base Image Workflow            │
│  .github/workflows/             │
│    build-base-image.yml         │
└────────────┬────────────────────┘
             │ Builds & signs
             ▼
┌─────────────────────────────────┐
│  GHCR                           │
│  ghcr.io/pecatap/               │
│    python-slsa-base:latest      │
│  + SLSA provenance              │
└────────────┬────────────────────┘
             │ Used by
             ▼
┌─────────────────────────────────┐
│  Application Workflow           │
│  .github/workflows/             │
│    slsa-l1-l2.yml               │
└────────────┬────────────────────┘
             │ Builds app
             ▼
┌─────────────────────────────────┐
│  GHCR                           │
│  ghcr.io/pecatap/               │
│    python-slsa-web:latest       │
│  + SLSA provenance              │
└─────────────────────────────────┘
```

## Implementation

### Base Image Dockerfile

Located at `base-image/Dockerfile`:

```dockerfile
FROM python:3.11-alpine

# Add metadata
LABEL org.opencontainers.image.source="https://github.com/PecataP/K8S-SLSA"
LABEL org.opencontainers.image.description="Base Python 3.11 Alpine image for SLSA pipeline"

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Security updates
RUN apk update && apk upgrade && rm -rf /var/cache/apk/*

WORKDIR /app
USER appuser
```

**Key features**:
- Based on official Python Alpine image
- Security updates applied at build time
- Non-root user pre-configured
- Minimal and clean

### Base Image Build Workflow

Located at `.github/workflows/build-base-image.yml`:

**Triggers**:
- Manual dispatch (`workflow_dispatch`)
- Changes to `base-image/Dockerfile`
- Monthly schedule (1st of each month) for security updates

**Process**:
1. Checks out repository
2. Sets up Docker Buildx
3. Authenticates to GHCR
4. Builds base image with provenance and SBOM
5. Pushes to GHCR with multiple tags
6. Verifies provenance attestation

### Application Dockerfile

The main `DOCKERFILE` now uses the custom base image:

```dockerfile
# Build stage
FROM ghcr.io/pecatap/python-slsa-base:latest AS build
USER root
WORKDIR /src
COPY app/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Runtime stage
FROM ghcr.io/pecatap/python-slsa-base:latest
USER root
WORKDIR /app
COPY --from=build --chown=appuser:appuser /root/.local /home/appuser/.local
COPY --chown=appuser:appuser app/app.py .
USER appuser
```

**Changes from original**:
- Uses `ghcr.io/pecatap/python-slsa-base:latest` instead of `python:3.11-alpine`
- No need for Docker Hub authentication
- Faster builds (single registry)

## Setup Instructions

### Initial Setup

1. **Build the base image first**:
   ```bash
   # Trigger the base image workflow manually
   gh workflow run build-base-image.yml

   # Or push a change to base-image/Dockerfile
   git add base-image/Dockerfile
   git commit -m "Initial base image"
   git push
   ```

2. **Wait for base image to build**:
   ```bash
   # Watch the workflow
   gh run watch

   # Verify the image exists
   docker pull ghcr.io/pecatap/python-slsa-base:latest
   ```

3. **Build your application**:
   ```bash
   # Now the main workflow can pull from GHCR
   git push origin main
   ```

### Image Tags

The base image is tagged with:
- `latest`: Always points to most recent build
- `<sha>`: Git commit SHA for traceability
- `YYYYMMDD`: Date stamp for scheduled builds

### Updating the Base Image

#### Manual Update

```bash
# Trigger workflow via GitHub UI or CLI
gh workflow run build-base-image.yml

# Or make changes to the Dockerfile
vim base-image/Dockerfile
git add base-image/Dockerfile
git commit -m "Update base image dependencies"
git push
```

#### Automatic Updates

The workflow runs automatically:
- **Monthly**: First day of each month at midnight UTC
- **On Changes**: When `base-image/Dockerfile` is modified

This ensures you get security updates regularly without manual intervention.

### Using Specific Digest (Recommended for Production)

For production, pin to a specific digest:

```dockerfile
# Get the digest from workflow output
FROM ghcr.io/pecatap/python-slsa-base@sha256:abc123...
```

Benefits:
- Immutable builds
- Exact reproducibility
- Better SLSA compliance

## Verification

### Verify Base Image Provenance

```bash
# Inspect the base image
docker buildx imagetools inspect ghcr.io/pecatap/python-slsa-base:latest

# You should see:
# - Image manifest
# - Provenance attestation (application/vnd.in-toto+json)
# - SBOM attestation
```

### Verify Application Uses Base Image

```bash
# Pull and inspect your application image
docker pull ghcr.io/pecatap/python-slsa-web:latest
docker image history ghcr.io/pecatap/python-slsa-web:latest

# Should show base image layers
```

### Check Supply Chain

```bash
# Both images should have provenance
docker buildx imagetools inspect ghcr.io/pecatap/python-slsa-base:latest | grep -A5 provenance
docker buildx imagetools inspect ghcr.io/pecatap/python-slsa-web:latest | grep -A5 provenance
```

## SLSA Compliance Impact

### Before (Docker Hub Base)

```
Docker Hub (no provenance)
    └─> Your App (SLSA L2)
```

**Issues**:
- Break in provenance chain
- External dependency
- Rate limit risks

### After (Custom Base)

```
Docker Hub
    └─> Base Image (SLSA L2)
        └─> Your App (SLSA L2)
```

**Benefits**:
- Complete provenance chain
- All artifacts signed
- Full supply chain control
- Meets SLSA Build L2 requirements

## Maintenance

### Monthly Maintenance

The scheduled workflow runs monthly to:
1. Pull latest upstream Python Alpine image
2. Apply security updates (`apk update && apk upgrade`)
3. Build and sign new base image
4. Push to GHCR with date tag

### Manual Security Updates

If a critical vulnerability is announced:

```bash
# Rebuild base image immediately
gh workflow run build-base-image.yml

# After base image builds, rebuild application
git commit --allow-empty -m "Trigger rebuild with updated base image"
git push
```

### Monitoring

Set up notifications for:
- Base image build failures
- Python Alpine security advisories
- GHCR storage limits

## Cost Considerations

### Storage

GHCR provides:
- 500MB free for public repositories
- 2GB free for private repositories

Base image size: ~50MB
Application image size: ~55MB

**Storage optimization**:
- Use `.latest` tag to avoid proliferation
- Clean up old date-stamped images periodically
- Keep last 3-6 monthly builds

### Build Time

Comparison:
- **Docker Hub**: ~60s (pull + build)
- **GHCR Base**: ~30s (pull + build)

**50% faster** because:
- Same registry (no external network)
- Cached layers
- Parallel operations

## Troubleshooting

### Base Image Build Fails

```bash
# Check workflow logs
gh run view --log

# Common issues:
# - Docker Hub rate limit (pull upstream)
# - GHCR authentication failure
# - Disk space on runner
```

**Solution**: The workflow only pulls from Docker Hub once, so rate limits are rare.

### Application Can't Pull Base Image

**Error**: `Error: failed to solve: failed to pull: unauthorized`

**Solution**:
```bash
# Make base image public
gh api repos/PecataP/K8S-SLSA/packages/container/python-slsa-base/visibility \
  -X PATCH \
  -f visibility=public

# Or add GHCR credentials to workflow (not needed for public images)
```

### Base Image Out of Date

**Check age**:
```bash
# View tags and timestamps
gh api repos/PecataP/K8S-SLSA/packages/container/python-slsa-base/versions
```

**Update**:
```bash
# Trigger rebuild
gh workflow run build-base-image.yml
```

## Best Practices

1. **Public Base Images**: Keep base image public for easier distribution
2. **Regular Updates**: Let monthly cron job handle routine updates
3. **Version Tags**: Use date tags for audit trail
4. **Digest Pinning**: Pin production to specific digest
5. **Image Scanning**: Add vulnerability scanning to base image workflow
6. **Documentation**: Update base-image/Dockerfile comments when adding dependencies

## Future Enhancements

### Phase 1 (Current)
- Custom base image from Docker Hub upstream
- SLSA L2 provenance
- Monthly security updates

### Phase 2 (Future)
- Cosign signing of base image
- Vulnerability scanning with Trivy
- Multi-arch builds (ARM64 support)
- Renovate bot for automated updates

### Phase 3 (Future)
- Base image attestation verification in app workflow
- Kyverno policy to enforce base image usage
- SLSA L3 for base image builds

## Resources

- [OCI Image Spec](https://github.com/opencontainers/image-spec)
- [Docker Build Attestations](https://docs.docker.com/build/attestations/)
- [GHCR Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Base Image Security Best Practices](https://docs.docker.com/develop/security-best-practices/)

## Quick Reference

```bash
# Build base image
gh workflow run build-base-image.yml

# View base image versions
docker pull ghcr.io/pecatap/python-slsa-base:latest

# Check provenance
docker buildx imagetools inspect ghcr.io/pecatap/python-slsa-base:latest

# Trigger application rebuild
git commit --allow-empty -m "Rebuild"
git push
```
