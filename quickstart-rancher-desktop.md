# OpsContinuum Chart quick start (Rancher Desktop)

Commands to deploy the OpsContinuum chart on a fresh Rancher Desktop cluster.

The GitRepository and Kustomization resources must be named `opsc` exactly,
because the HelmRelease references this name in its `sourceRef`.

## Prerequisites

- Rancher Desktop with Kubernetes enabled
- `kubectl` configured

## Step 1: install FluxCD

```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

# Wait for controllers
kubectl -n flux-system rollout status deployment/helm-controller
kubectl -n flux-system rollout status deployment/source-controller
```

## Step 2: install the ECK CRDs

```bash
kubectl create -f https://download.elastic.co/downloads/eck/3.2.0/crds.yaml
```

## Step 3: create the GitRepository

```bash
kubectl apply -f - <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: opsc
  namespace: flux-system
spec:
  interval: 5m
  url: https://github.com/opscontinuum/flux-base.git
  ref:
    branch: main
EOF
```

## Step 4: create the Kustomization (Rancher Desktop)

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

## Step 5: monitor the deployment

```bash
# Watch HelmReleases
kubectl get helmrelease -A -w

# Check all pods
kubectl get pods -A

# Force reconciliation if needed
kubectl annotate gitrepository opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

## Step 6: add hosts entries

Add to `C:\Windows\System32\drivers\etc\hosts` (run Notepad as Administrator):

```
127.0.0.1 argocd.dev.yourdomain.local
127.0.0.1 gitlab.dev.yourdomain.local
127.0.0.1 registry.dev.yourdomain.local
127.0.0.1 minio.dev.yourdomain.local
127.0.0.1 kas.dev.yourdomain.local
127.0.0.1 n8n.dev.yourdomain.local
127.0.0.1 kibana.dev.yourdomain.local
```

## Step 7: access the services

| Service | URL |
|---------|-----|
| Argo CD | https://argocd.dev.yourdomain.local |
| GitLab | https://gitlab.dev.yourdomain.local |
| Kibana | https://kibana.dev.yourdomain.local |
| n8n | https://n8n.dev.yourdomain.local |

### Get credentials

```bash
# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# GitLab root password
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Elasticsearch password
kubectl -n elastic-stack get secret elasticsearch-es-elastic-user \
  -o jsonpath="{.data.elastic}" | base64 -d && echo
```

## Troubleshooting

### The OpsContinuum HelmRelease fails on first install

The `opsc` HelmRelease may fail on initial deployment with an error about
`Certificate` resources not found. cert-manager's CRDs are not yet available
when the chart tries to create Certificate resources.

Wait for cert-manager to deploy fully, then force a retry:

```bash
kubectl annotate helmrelease opsc -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### Force a HelmRelease retry

If a HelmRelease fails, force a retry:

```bash
kubectl annotate helmrelease <name> -n flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### HelmRelease stuck at the retry limit

If a HelmRelease has exhausted its retry attempts and will not reconcile,
suspend and resume it:

```bash
kubectl patch helmrelease <name> -n flux-system --type=merge -p '{"spec":{"suspend":true}}'
kubectl patch helmrelease <name> -n flux-system --type=merge -p '{"spec":{"suspend":false}}'
```

### Check HelmRelease status

```bash
kubectl get helmrelease -A
kubectl describe helmrelease <name> -n flux-system
```

### Check Flux logs

```bash
kubectl logs -n flux-system deployment/helm-controller --tail=50
kubectl logs -n flux-system deployment/kustomize-controller --tail=50
```

### GitLab Runner registration

The GitLab Runner pod may show registration errors until GitLab is fully up.
The runner retries registration on its own. If the errors persist, check the
runner logs:

```bash
kubectl logs -n gitlab-runner -l app=gitlab-runner --tail=50
```
