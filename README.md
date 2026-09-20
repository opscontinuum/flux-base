# OpsContinuum Chart

A curated Kubernetes platform deployment using GitOps (FluxCD) that includes:

- **Cert-Manager** - TLS certificate management
- **ECK Operator 3.x** - Elastic Cloud on Kubernetes (supports Elastic 9.x)
- **Elastic Stack 9.x** - Elasticsearch, Kibana, Fleet Server, Elastic Agent, APM Server
- **OpenTelemetry Operator** - Auto-instrumentation for distributed tracing
- **GitLab** - DevOps platform (CE edition)
- **GitLab Runner** - CI/CD runner
- **ArgoCD** - GitOps continuous delivery
- **n8n** - Workflow automation

---

## What this is

This repository is the **Flux layer**: a single Helm chart, deployed by FluxCD, that
bootstraps the underlying platform *capability* of a Kubernetes cluster. It is not an
application repository, and it does not describe the workloads that eventually run on
the cluster.

### The boundary: Flux owns capability, Argo owns instances

This chart deploys ArgoCD as one of its packages, and that is a deliberate boundary,
not an accident:

- **Flux (this repository) owns capability.** It reconciles the platform itself:
  ingress, certificates, logging, CI/CD infrastructure, and ArgoCD as a piece of
  platform tooling. Changes here answer the question "what can this cluster do?"
- **Argo CD owns instances.** Once ArgoCD is running, it takes over managing the
  application workloads deployed on top of the platform, through its own
  Application/ApplicationSet sources. Changes there answer the question "what is
  actually running right now?"

Do not add application-specific manifests to this repository. Application state
belongs in ArgoCD-managed sources, once the platform capability that this chart
provides exists.

---

## Before you deploy

The chart ships with **no defaults** for the values below. Rendering fails loudly
with a clear error until each one is set, rather than silently deploying against
somebody else's domain, email address, or a default password shipped in a public
chart. Set these first:

| Value | Purpose |
|-------|---------|
| `domain` | Base domain for all ingress hosts |
| `certManager.acmeEmail` | Contact email for Let's Encrypt account registration and the Cloudflare DNS-01 solver |
| `gitlab.postgresqlPassword` | Password for the bundled GitLab PostgreSQL StatefulSet |
| `gitlab.postgresqlPostgresPassword` | Password for the bundled PostgreSQL superuser |
| `gitlab.redisPassword` | Password for the bundled GitLab Redis StatefulSet |

Generate strong passwords with, for example:

```bash
openssl rand -base64 24
```

See "Setting real values locally" below for where these actually go. They do not
belong in this public tree.

---

## Environment Overlays

This chart uses **Kustomize overlays** for multi-environment support. Choose the overlay that matches your deployment target:

| Environment | Overlay Path | Description |
|-------------|--------------|-------------|
| **Rancher Desktop** | `overlays/rancher-desktop` | Local development with built-in Traefik |
| **Harvester** | `overlays/harvester` | Harvester HCI cluster with Traefik (secondary) + MetalLB |

### Harvester Architecture Note

> **IMPORTANT:** Harvester uses a built-in nginx ingress controller on ports 80/443 for the Harvester admin UI. **DO NOT replace or disable nginx** - doing so will break the Harvester admin interface.
>
> The Harvester overlay deploys Traefik as a **secondary** ingress controller that runs alongside nginx:
> - **nginx** remains on the node's primary IP (ports 80/443) for Harvester admin
> - **Traefik** gets a separate LoadBalancer IP from MetalLB for your applications
>
> This dual-ingress setup keeps Harvester functional while providing Traefik for your workloads.

### Repository Structure

```
base/                           # Base Kustomize resources (do not deploy directly)
├── chart/                      # Helm chart with templates
│   ├── values.yaml             # Default values (override in overlay)
│   └── templates/
├── helmrelease.yaml            # FluxCD HelmRelease resource
└── kustomization.yaml

overlays/
├── rancher-desktop/            # Local development overlay
│   ├── kustomization.yaml
│   └── helmrelease-patch.yaml  # Rancher Desktop specific settings
│
└── harvester/                  # Harvester overlay
    ├── kustomization.yaml
    └── helmrelease-patch.yaml  # Harvester specific settings (edit this!)
```

### Configuring Your Environment

1. **Choose your overlay** based on your target cluster
2. **Edit the overlay's `helmrelease-patch.yaml`** to set your domain and other settings

**For Harvester** (`overlays/harvester/helmrelease-patch.yaml`):
```yaml
# Replace yourdomain.local with your domain
domain: yourdomain.local

# Set your MetalLB IP range
metallb:
  addressPool:
    addresses:
      - "192.168.1.240-192.168.1.250"  # Your network's available IPs
```

**For Rancher Desktop** (`overlays/rancher-desktop/helmrelease-patch.yaml`):
```yaml
# Local development domain (uses hosts file)
domain: dev.yourdomain.local
```

### Hosts File Setup

For local development or when DNS is not configured, add entries to your hosts file.

#### Windows

1. Open Notepad **as Administrator** (right-click -> "Run as administrator")
2. Open File -> Open and navigate to `C:\Windows\System32\drivers\etc\hosts`
3. Add the entries below and save

#### Linux / macOS

```bash
sudo nano /etc/hosts
# Add entries below, then Ctrl+O to save, Ctrl+X to exit
```

#### Hosts Entries

**For Rancher Desktop (dev.yourdomain.local):**
```
127.0.0.1 argocd.dev.yourdomain.local
127.0.0.1 gitlab.dev.yourdomain.local
127.0.0.1 registry.dev.yourdomain.local
127.0.0.1 minio.dev.yourdomain.local
127.0.0.1 kas.dev.yourdomain.local
127.0.0.1 n8n.dev.yourdomain.local
127.0.0.1 kibana.dev.yourdomain.local
```

**For Harvester (using MetalLB IP):**
```
# Replace 192.168.1.240 with your MetalLB assigned IP (check with: kubectl get svc -n traefik)
192.168.1.240 argocd.yourdomain.local
192.168.1.240 gitlab.yourdomain.local
192.168.1.240 registry.yourdomain.local
192.168.1.240 minio.yourdomain.local
192.168.1.240 kas.yourdomain.local
192.168.1.240 n8n.yourdomain.local
192.168.1.240 kibana.yourdomain.local
```

---

## Quick Start

### Prerequisites

- **Kubernetes Cluster** (v1.28+) - Rancher Desktop, k3s, or compatible
- **Traefik Ingress Controller** (included with k3s/Rancher Desktop, deployed via overlay for Harvester)
- **kubectl** configured to access your cluster
- **helm** (v3.x)

### Create Your Own Repository

**Important:** Create your own copy of this chart. You will configure your deployment in your repository, and real values never belong in a public repository.

**Option A: Fork on GitHub**

1. Click "Fork" on GitHub to create your own copy
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_FORK.git
   cd YOUR_FORK
   ```

**Option B: Create a new repository**

```bash
# Clone this repository
git clone https://github.com/opscontinuum/flux-base.git
cd flux-base

# Remove the original remote and add your own
git remote remove origin
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# Push to your repository
git push -u origin main
```

---

## Step 1: Install FluxCD

```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

# Wait for controllers to be ready
kubectl -n flux-system rollout status deployment/helm-controller
kubectl -n flux-system rollout status deployment/source-controller
```

## Step 2: Install ECK CRDs

The Elastic Stack requires ECK Operator CRDs:

```bash
kubectl create -f https://download.elastic.co/downloads/eck/3.2.0/crds.yaml
```

## Step 3: Create Required Secrets

**These secrets must be created before deploying the chart. Real credentials never belong in git.**

### Option A: Let's Encrypt with Cloudflare (Production)

```bash
# Create cert-manager namespace
kubectl create namespace cert-manager

# Create Cloudflare API token secret
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_API_TOKEN
```

To create a Cloudflare API token:
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) -> My Profile -> API Tokens
2. Create token with permissions: `Zone:Zone:Read` and `Zone:DNS:Edit`
3. Zone Resources: Include -> Specific zone -> your domain

### Option B: Let's Encrypt with Route53 (Production)

```bash
kubectl create namespace cert-manager

kubectl create secret generic route53-credentials \
  --namespace cert-manager \
  --from-literal=access-key-id=YOUR_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_SECRET_KEY
```

### Option C: Self-Signed Certificates (Development)

No secrets required. Self-signed CA is created automatically.

## Step 4: Configure Your Deployment

Edit the appropriate overlay's `helmrelease-patch.yaml`:

**For Rancher Desktop:** `overlays/rancher-desktop/helmrelease-patch.yaml`
**For Harvester:** `overlays/harvester/helmrelease-patch.yaml`

```yaml
# Set your domain
domain: yourdomain.local

# Set your ACME contact email (required, no default)
certManager:
  acmeEmail: you@yourdomain.local

# Choose certificate issuer
# Options: "self-signed", "letsencrypt-staging", "letsencrypt-prod"
clusterIssuer: self-signed

# Set the bundled GitLab PostgreSQL/Redis passwords (required, no default)
gitlab:
  postgresqlPassword: "generate with: openssl rand -base64 24"
  postgresqlPostgresPassword: "generate with: openssl rand -base64 24"
  redisPassword: "generate with: openssl rand -base64 24"
```

### Enable/Disable Components

```yaml
certManager:
  enabled: true

eckOperator:
  enabled: true

elasticStack:
  enabled: true

gitlab:
  enabled: true

gitlabRunner:
  enabled: true

argocd:
  enabled: true

n8n:
  enabled: true
```

**Commit and push your configuration changes:**

```bash
git add overlays/
git commit -m "Configure for my environment"
git push origin main
```

## Step 5: Create FluxCD Resources

> **The GitRepository and Kustomization resources must be named `opsc` exactly.**
> The HelmRelease templates reference this name in their `sourceRef`. Renaming
> the resource without updating every reference means Flux reconciles nothing,
> silently, with no error to point you back here.

### Create GitRepository

For public repositories:

```bash
kubectl apply -f - <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 5m
  url: https://github.com/YOUR_USERNAME/YOUR_FORK.git
  ref:
    branch: main
EOF
```

For private repositories:

```bash
# Create authentication secret
kubectl create secret generic opsc-git-auth \
  --namespace flux-system \
  --from-literal=username=YOUR_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN

# Create GitRepository with secret reference
kubectl apply -f - <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 5m
  url: https://github.com/YOUR_USERNAME/YOUR_FORK.git
  ref:
    branch: main
  secretRef:
    name: opsc-git-auth
EOF
```

### Create Kustomization (for overlay deployment)

**For Rancher Desktop:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 10m
  path: ./overlays/rancher-desktop
  prune: true
  sourceRef:
    kind: GitRepository
    name: opsc
EOF
```

**For Harvester:**

```bash
kubectl apply -f - <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 10m
  path: ./overlays/harvester
  prune: true
  sourceRef:
    kind: GitRepository
    name: opsc
EOF
```

## Step 6: Monitor Deployment

```bash
# Watch Kustomizations reconcile
kubectl get kustomizations -A -w

# Check all pods
kubectl get pods -A

# Force immediate reconciliation
kubectl annotate gitrepository opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### Expected Deployment Order

1. cert-manager -> Ready
2. eck-operator -> Ready
3. elastic-stack, opentelemetry-operator, argocd, n8n -> Ready (parallel)
4. gitlab -> Ready (takes 5-10 minutes)
5. gitlab-runner -> Ready

## Step 7: Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | https://argocd.dev.yourdomain.local | `admin` / see below |
| GitLab | https://gitlab.dev.yourdomain.local | `root` / see below |
| Kibana | https://kibana.dev.yourdomain.local | `elastic` / see below |
| n8n | https://n8n.dev.yourdomain.local | Create on first login |

### Get Credentials

```bash
# ArgoCD admin password
kubectl -n argocd get secret argocd-argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# GitLab root password
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Elasticsearch password
kubectl -n elastic-stack get secret elasticsearch-es-elastic-user \
  -o jsonpath="{.data.elastic}" | base64 -d && echo
```

---

## Setting real values locally

**⚠️ WARNING: this repository is public. Your real domain, your real ACME contact
email, and the passwords for the bundled GitLab PostgreSQL and Redis instances are
real values that must never be committed or pushed here, to this repository or to
any fork of it.**

For local rendering and testing (`helm template`, `helm lint`) before you configure
your actual deployment, create a gitignored file, for example
`overlays/<your-environment>/values.local.yaml`:

```yaml
domain: your-real-domain.example
certManager:
  acmeEmail: you@your-real-domain.example
gitlab:
  postgresqlPassword: "<output of: openssl rand -base64 24>"
  postgresqlPostgresPassword: "<output of: openssl rand -base64 24>"
  redisPassword: "<output of: openssl rand -base64 24>"
```

Render locally with:

```bash
helm template ./base/chart \
  -f overlays/<your-environment>/values-patch.yaml \
  -f overlays/<your-environment>/values.local.yaml
```

`values.local.yaml` and any `*.local.yaml` file are already excluded by
`.gitignore`. If your real GitOps deployment needs these values committed
somewhere for Flux to read, keep that in a **separate, private** repository, or
in a Kubernetes Secret referenced by your overlay, never in this public tree.

---

## Secrets Reference

All secrets are created in-cluster using `kubectl`. **Never commit secrets to git.**

| Secret | Namespace | Purpose | When Required |
|--------|-----------|---------|---------------|
| `cloudflare-api-token` | cert-manager | Cloudflare DNS-01 challenge | Let's Encrypt with Cloudflare |
| `route53-credentials` | cert-manager | Route53 DNS-01 challenge | Let's Encrypt with Route53 |
| `opsc-git-auth` | flux-system | Private git repository access | Private repos only |

### Secrets Created Automatically

These secrets are created by the chart and do not require manual setup, other than the required values listed under "Before you deploy":

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `gitlab-gitlab-runner-secret` | gitlab | GitLab Runner registration token |
| `gitlab-postgresql-password` | gitlab | Bundled PostgreSQL credentials (from `gitlab.postgresqlPassword`) |
| `gitlab-redis-password` | gitlab | Bundled Redis credentials (from `gitlab.redisPassword`) |
| `elasticsearch-es-elastic-user` | elastic-stack | Elasticsearch admin password |
| `argocd-argocd-initial-admin-secret` | argocd | ArgoCD admin password |
| `gitlab-gitlab-initial-root-password` | gitlab | GitLab root password |

---

## Updating Your Deployment

With GitOps, updates are automatic:

```bash
# Make changes to your overlay's helmrelease-patch.yaml
vim overlays/rancher-desktop/helmrelease-patch.yaml

# Commit and push
git add . && git commit -m "Update configuration" && git push

# Flux auto-syncs within 5 minutes, or force immediately:
kubectl annotate gitrepository opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

---

## Resource Requirements

Minimum recommended resources (all components enabled):

| Component | CPU Request | Memory Request | Memory Limit | Notes |
|-----------|-------------|----------------|--------------|-------|
| cert-manager | 50m | 64Mi | 128Mi | |
| eck-operator | 100m | 150Mi | 256Mi | |
| elasticsearch | 500m | 1Gi | 2Gi | Single node; increase for HA |
| kibana | 250m | 768Mi | 1Gi | **Requires 768Mi+ to start** |
| apm-server | 100m | 256Mi | 512Mi | |
| fleet-server | 100m | 256Mi | 512Mi | |
| elastic-agent | 200m | 512Mi | 1Gi | |
| opentelemetry-operator | 100m | 128Mi | 256Mi | |
| gitlab | 1000m | 4Gi | 6Gi | Includes all subcomponents |
| gitlab-runner | 100m | 128Mi | 256Mi | |
| argocd | 250m | 256Mi | 512Mi | |
| n8n | 100m | 256Mi | 512Mi | |

**Minimum Total:** ~3 CPU cores, ~8GB RAM

> **Important:** Kibana 9.x requires at least 768Mi of memory to start successfully. The default 512Mi limit will cause OOM (out of memory) crashes. The overlays are configured with appropriate limits, but if you customise resources, ensure Kibana has sufficient memory.

### Environment-Specific Resources

The overlays configure different resource allocations:

- **Rancher Desktop:** Lighter resources for local development (~8GB RAM total)
- **Harvester:** Production-ready resources for cluster deployment (~16GB+ RAM recommended)

---

## Troubleshooting

### Check Kustomization Status

```bash
kubectl get kustomizations -A
kubectl describe kustomization opsc -n flux-system
```

### Check Flux Logs

```bash
kubectl logs -n flux-system deployment/kustomize-controller
kubectl logs -n flux-system deployment/helm-controller
```

### Check ClusterIssuers

```bash
kubectl get clusterissuers
kubectl describe clusterissuer self-signed
```

### Check Certificates

```bash
kubectl get certificates -A
kubectl describe certificate <name> -n <namespace>
```

### Force Reconciliation

```bash
# Reconcile git source
kubectl annotate gitrepository opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite

# Reconcile Kustomization
kubectl annotate kustomization opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

---

## Uninstalling

```bash
# Remove Kustomization and GitRepository
kubectl delete kustomization opsc -n flux-system
kubectl delete gitrepository opsc -n flux-system

# Remove FluxCD (optional)
kubectl delete -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

# Remove ECK CRDs (optional)
kubectl delete -f https://download.elastic.co/downloads/eck/3.2.0/crds.yaml

# Clean up namespaces
kubectl delete namespace cert-manager eck-operator gitlab gitlab-runner \
  argocd n8n elastic-stack opentelemetry-operator-system
```

---

## Architecture

### Namespace Layout

```
flux-system                    - FluxCD controllers + Kustomizations
cert-manager                   - Certificate management
eck-operator                   - ECK Operator 3.x
elastic-stack                  - Elasticsearch, Kibana, Fleet, Agent, APM
opentelemetry-operator-system  - OpenTelemetry Operator
gitlab                         - GitLab CE + PostgreSQL + Redis + MinIO
gitlab-runner                  - GitLab Runner
argocd                         - ArgoCD (platform capability; owns application instances once deployed)
n8n                            - n8n workflow automation
```

### Component Dependencies

```
FluxCD + ECK CRDs (prerequisites)
    |
    +-- cert-manager
            |
            +-- eck-operator
            |       |
            |       +-- elastic-stack
            |
            +-- opentelemetry-operator
            |
            +-- argocd
            |
            +-- n8n
            |
            +-- gitlab
                    |
                    +-- gitlab-runner
```
