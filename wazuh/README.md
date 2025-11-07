# Wazuh Security Monitoring

This directory contains configuration files for deploying Wazuh agents in your Kubernetes cluster for comprehensive security monitoring.

## What is Wazuh?

Wazuh is an open-source security platform that provides:
- **Threat Detection**: Real-time threat detection and incident response
- **File Integrity Monitoring (FIM)**: Track changes to critical files
- **Vulnerability Detection**: Scan for known CVEs in your containers
- **Container Security**: Monitor Docker/containerd events
- **Compliance**: CIS Kubernetes and Docker benchmarks
- **Log Analysis**: Centralized log collection and analysis

## Architecture

The setup includes:
1. **Wazuh Manager** (separate deployment or external) - Central management server
2. **Wazuh Agents** (DaemonSet) - Deployed on each Kubernetes node

## Prerequisites

You need either:

### Option 1: External Wazuh Manager
Deploy Wazuh Manager separately following the [official documentation](https://documentation.wazuh.com/current/deployment-options/index.html).

### Option 2: In-Cluster Wazuh Manager

```bash
# Add Wazuh Helm repository
helm repo add wazuh https://wazuh.github.io/wazuh-kubernetes
helm repo update

# Install Wazuh (Manager + Indexer + Dashboard)
helm install wazuh wazuh/wazuh -n wazuh --create-namespace \
  --set wazuh-manager.replicas=1 \
  --set wazuh-indexer.replicas=1
```

## Installation

### 1. Configure Wazuh Manager Address

Edit `wazuh-agent-daemonset.yaml` and update the `WAZUH_MANAGER` environment variable:

```yaml
- name: WAZUH_MANAGER
  value: "YOUR_WAZUH_MANAGER_IP_OR_HOSTNAME"
```

### 2. Set Agent Registration Password

Edit `wazuh-rbac.yaml` and set a strong password:

```yaml
stringData:
  password: "YourStrongPassword123!"
```

This password must match the one configured in your Wazuh Manager at `/var/ossec/etc/authd.pass`.

### 3. Deploy Wazuh Components

```bash
# Create namespace and RBAC
kubectl apply -f wazuh-rbac.yaml

# Deploy agent configuration
kubectl apply -f wazuh-agent-config.yaml

# Deploy agents on all nodes
kubectl apply -f wazuh-agent-daemonset.yaml

# Verify deployment
kubectl get pods -n wazuh
kubectl logs -n wazuh -l app=wazuh-agent
```

## Security Features Monitored

### 1. File Integrity Monitoring
Monitors critical directories:
- `/etc/` - System configuration
- `/usr/bin/`, `/usr/sbin/` - Binaries
- `/boot/` - Boot files
- `/etc/kubernetes/` - K8s configuration
- `/var/lib/kubelet/` - Kubelet data

### 2. Container Security
- Docker/containerd events
- Container lifecycle monitoring
- Image scanning for vulnerabilities

### 3. CIS Benchmarks
Automated compliance checks:
- CIS Kubernetes Benchmark
- CIS Docker Benchmark

### 4. Vulnerability Detection
Scans for CVEs in:
- Ubuntu packages
- Debian packages
- Red Hat packages
- Alpine packages

### 5. Log Analysis
Monitors system logs:
- `/var/log/messages`
- `/var/log/secure`
- `/var/log/audit/audit.log`

## Accessing Wazuh Dashboard

If you deployed Wazuh in-cluster:

```bash
# Port forward to access dashboard
kubectl port-forward -n wazuh svc/wazuh-dashboard 443:443

# Access at: https://localhost:443
# Default credentials: admin / admin (change immediately)
```

## Integration with SLSA Pipeline

### Monitor CI/CD Security Events

Wazuh can monitor your SLSA pipeline:

1. **Image Build Events**: Track when images are built
2. **Signing Events**: Monitor Cosign signing operations
3. **Deployment Events**: Track when images are deployed
4. **Policy Violations**: Alert on Kyverno policy failures

### Custom Rules for SLSA

Create custom Wazuh rules to alert on:
- Unsigned images deployed
- Image pull from unapproved registry
- SLSA provenance verification failures
- Kyverno policy violations

Example custom rule location: `/var/ossec/etc/rules/local_rules.xml`

## Monitoring Your Python Application

Wazuh will automatically monitor:
- Application logs
- Container resource usage
- Network connections
- File system changes
- Process execution

## Troubleshooting

### Agents Not Registering

```bash
# Check agent logs
kubectl logs -n wazuh -l app=wazuh-agent

# Common issues:
# 1. Incorrect WAZUH_MANAGER address
# 2. Wrong registration password
# 3. Firewall blocking ports 1514/1515
# 4. Manager not configured for agent registration
```

### Enable Agent Debug Mode

Edit the DaemonSet and add:

```yaml
env:
  - name: WAZUH_AGENT_DEBUG
    value: "2"  # 0=no debug, 1=debug, 2=more debug
```

### Check Manager Configuration

On the Wazuh Manager:

```bash
# Verify authd password is set
cat /var/ossec/etc/authd.pass

# Check active agents
/var/ossec/bin/agent_control -l

# View agent connection status
tail -f /var/ossec/logs/ossec.log
```

## Best Practices

1. **Regular Updates**: Keep Wazuh agents and manager updated
2. **Tune Alerts**: Configure alert thresholds to reduce noise
3. **Backup Configuration**: Regularly backup Wazuh rules and configuration
4. **Segregate Alerts**: Use different agent groups for dev/staging/prod
5. **Integration**: Integrate with SIEM/SOAR platforms for automated response

## Security Considerations

1. **Agent Privileges**: Wazuh agents run as privileged pods to monitor the host
2. **Network Access**: Ensure secure communication between agents and manager
3. **Authentication**: Use strong registration passwords
4. **TLS**: Enable TLS encryption for agent-manager communication (production)
5. **RBAC**: Limit Wazuh dashboard access with proper RBAC

## Resources

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh Kubernetes Deployment](https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/index.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Container Security with Wazuh](https://documentation.wazuh.com/current/docker-monitor/index.html)
