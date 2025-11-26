# Base image for Python SLSA application
# This creates a minimal, secure base image that we control
# Eliminates dependency on Docker Hub rate limits

FROM python:3.11-alpine

# Add metadata
LABEL org.opencontainers.image.source="https://github.com/PecataP/K8S-SLSA"
LABEL org.opencontainers.image.description="Base Python 3.11 Alpine image for SLSA pipeline"
LABEL org.opencontainers.image.licenses="MIT"

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Install any common dependencies you need across apps
# (Currently none, but you can add them here)

# Security: Update packages
RUN apk update && apk upgrade && rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /app

# Switch to non-root user by default
USER appuser
