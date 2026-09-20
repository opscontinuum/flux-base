# Harvester Cluster Deployment Guide

This document explains how to deploy the OpsContinuum chart on a Harvester cluster. Harvester has some unique characteristics that require additional configuration compared to Rancher Desktop or standard k3s clusters.

## Harvester-Specific Considerations

Harvester clusters come with pre-installed components that affect this deployment:

1. **nginx-ingress**: Harvester uses nginx-ingress for its management UI, bound to ports 80/443
2. **No LoadBalancer support**: Bare-metal Harvester doesn't have cloud LoadBalancer support by default
3. **RKE2 base**: Uses RKE2 which includes its own set of Helm charts in kube-system

### Components Enabled for Harvester (not needed for Rancher Desktop)

| Component | Why Needed for Harvester |
|-----------|-------------------------|
| **MetalLB** | Provides LoadBalancer service support for bare-metal clusters |
| **Traefik** | Separate ingress controller to avoid port conflicts with Harvester's nginx |

For **Rancher Desktop** or **k3s** with built-in Traefik, you can leave these disabled.

---

## Pre-Deployment Steps

### 1. Configure kubeconfig

After Harvester installation, download the kubeconfig from the Harvester UI and configure it:

```bash
# Copy the downloaded kubeconfig
cp ~/Downloads/local.yaml ~/.kube/config

# Or merge with your existing config.
# Consider renaming the context to something recognisable, e.g.:
kubectl config rename-context local harvester

# Verify connectivity
kubectl get nodes
```

### 2. Install FluxCD

```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

# Wait for controllers to be ready
kubectl -n flux-system rollout status deployment/helm-controller
kubectl -n flux-system rollout status deployment/source-controller
```

### 3. Install Required CRDs

The chart uses CRDs that must be installed before the chart can deploy:

```bash
# ECK Operator CRDs (for Elasticsearch/Kibana)
kubectl create -f https://download.elastic.co/downloads/eck/3.2.0/crds.yaml

# Traefik CRDs (for IngressRoute resources)
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml

# MetalLB CRDs (for IPAddressPool resources)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/crd/bases/metallb.io_ipaddresspools.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/crd/bases/metallb.io_l2advertisements.yaml
```

### 4. Create Required Secrets

```bash
# Create cert-manager namespace
kubectl create namespace cert-manager

# Create Cloudflare API token secret (for Let's Encrypt DNS-01 challenge)
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN
```

---

## Chart Configuration for Harvester

### values.yaml Changes

Enable MetalLB and Traefik in your overlay's `helmrelease-patch.yaml` (`overlays/harvester/helmrelease-patch.yaml`):

```yaml
# Enable Traefik with LoadBalancer mode (not hostNetwork to avoid port conflicts)
traefik:
  enabled: true
  hostNetwork:
    enabled: false
  service:
    enabled: true
    type: LoadBalancer

# Enable MetalLB for LoadBalancer support
metallb:
  enabled: true
  addressPool:
    name: default-pool
    # Use IPs that don't conflict with Harvester's own management VIP
    # Note: Harvester's ingress-expose service will claim one IP from this pool
    addresses: ["192.168.1.240-192.168.1.250"]  # Replace with your network's available IPs
```

**Important**: Harvester's `ingress-expose` service (for the management UI) is a LoadBalancer type and will claim an IP from the MetalLB pool. Make sure to allocate at least 2 IPs so Traefik can get one.

Remember to also set `domain`, `certManager.acmeEmail`, and the `gitlab.postgresqlPassword` / `gitlab.postgresqlPostgresPassword` / `gitlab.redisPassword` values described in the top-level README before deploying; the chart will not render without them.

---

## Deployment Steps

### 1. Create Git Authentication Secret (for private repos)

```bash
kubectl create secret generic opsc-git-auth \
  --namespace flux-system \
  --from-literal=username=YOUR_GIT_USERNAME \
  --from-literal=password=YOUR_GIT_PAT
```

### 2. Create GitRepository

```bash
kubectl apply -f - <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 5m
  url: https://gitlab.example.test/YOUR_ORG/YOUR_REPO.git
  ref:
    branch: main
  secretRef:
    name: opsc-git-auth
EOF
```

### 3. Create HelmRelease

```bash
kubectl apply -f - <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 10m
  timeout: 15m
  chart:
    spec:
      chart: ./chart
      sourceRef:
        kind: GitRepository
        name: opsc
        namespace: flux-system
      reconcileStrategy: Revision
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
    cleanupOnFail: true
EOF
```

### 4. Monitor Deployment

```bash
# Watch HelmReleases
kubectl get helmrelease -A -w

# Check all pods
kubectl get pods -A

# Force immediate reconciliation if needed
kubectl annotate gitrepository opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

---

## Post-Deployment Configuration

### Check Service IPs

```bash
# Verify Traefik got a LoadBalancer IP
kubectl get svc -n traefik
# Example output:
# NAME              TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)
# traefik-traefik   LoadBalancer   10.43.12.34     192.168.1.241  80:30772/TCP,443:31738/TCP

# Verify MetalLB IP pool
kubectl get ipaddresspool -n metallb-system
```

### Configure DNS or Hosts File

Point your domain names to Traefik's LoadBalancer IP (illustrative example: `192.168.1.241`):

```
192.168.1.241 argocd.yourdomain.local
192.168.1.241 gitlab.yourdomain.local
192.168.1.241 n8n.yourdomain.local
192.168.1.241 kibana.yourdomain.local
```

Or configure proper DNS A records if using a real domain with Let's Encrypt.

---

## Troubleshooting

### Namespace Stuck in Terminating

If namespaces get stuck during cleanup, check for resources with finalizers:

```bash
kubectl get ns <namespace> -o jsonpath='{.status.conditions}'

# Remove finalizers from blocking resources
kubectl get challenges.acme.cert-manager.io -n <namespace> -o name | \
  xargs -r kubectl patch -n <namespace> -p '{"metadata":{"finalizers":null}}' --type=merge
```

### MetalLB Not Assigning IPs

Check the controller logs:

```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller
```

Common issues:
- IP range exhausted (Harvester's ingress-expose claims one)
- IPAddressPool or L2Advertisement CRDs not installed

### Traefik Service Pending

If Traefik's LoadBalancer IP shows `<pending>`:

1. Ensure MetalLB is running: `kubectl get pods -n metallb-system`
2. Check IPAddressPool exists: `kubectl get ipaddresspool -n metallb-system`
3. Verify L2Advertisement exists: `kubectl get l2advertisement -n metallb-system`

---

## Architecture Summary

```
Harvester Cluster (illustrative: 192.168.1.1 - management VIP)
├── kube-system
│   └── rke2-ingress-nginx (ports 80/443 on node, LoadBalancer for Harvester admin)
│
├── metallb-system
│   └── MetalLB (manages your chosen IP pool, e.g. 192.168.1.240-192.168.1.250)
│
├── traefik
│   └── Traefik (LoadBalancer, gets one IP from the MetalLB pool)
│       ├── IngressRoutes for argocd, gitlab, n8n, kibana
│       └── TLS via cert-manager
│
├── cert-manager (Let's Encrypt via Cloudflare DNS-01)
├── argocd
├── gitlab
├── gitlab-runner
├── n8n
├── elastic-stack (elasticsearch, kibana, fleet, apm)
└── opentelemetry-operator-system
```

---

## Summary of Harvester-Specific Steps

1. Install FluxCD
2. Install ECK CRDs (for Elasticsearch)
3. Install Traefik CRDs (for IngressRoute)
4. Install MetalLB CRDs (for IPAddressPool)
5. Create Cloudflare API token secret
6. Enable MetalLB with an IP range (2+ IPs, since Harvester's ingress-expose claims one)
7. Enable Traefik with LoadBalancer mode (not hostNetwork)
8. Set `domain`, `certManager.acmeEmail`, and the GitLab PostgreSQL/Redis passwords (required, see README)
9. Create the FluxCD GitRepository and HelmRelease, both named `opsc`
10. Configure DNS/hosts to point to Traefik's LoadBalancer IP
