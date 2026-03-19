# postgres-cluster Helm Chart

PostgreSQL HA Cluster using CloudNativePG. One chart, three storage backends.

## Folder Structure

```
postgres-cluster/
├── Chart.yaml
├── values.yaml            ← default values (local dev)
├── values-local.yaml      ← local-path storage override
├── values-longhorn.yaml   ← Longhorn storage override
├── values-gke.yaml        ← GKE PD storage override
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── secret.yaml
    ├── storageclass.yaml  ← auto-configures based on storageType
    ├── cluster.yaml       ← CloudNativePG Cluster resource
    ├── expose.yaml        ← optional LoadBalancer / NodePort
    └── NOTES.txt          ← shown after helm install
```

---

## Prerequisites

```bash
# CNPG operator must be installed first
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace

# For local storage — install local-path provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# For Longhorn — install Longhorn first
helm repo add longhorn https://charts.longhorn.io
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system --create-namespace
```

---

## Usage

### Local development (quickest)
```bash
helm install pg ./postgres-cluster -f values-local.yaml
```

### With Longhorn storage
```bash
helm install pg ./postgres-cluster -f values-longhorn.yaml \
  --set credentials.password=YourPassword
```

### On GKE with native PD storage
```bash
helm install pg ./postgres-cluster -f values-gke.yaml \
  --set credentials.password=YourPassword
```

### Custom password without editing files
```bash
helm install pg ./postgres-cluster \
  -f values-local.yaml \
  --set credentials.password=MySecurePassword
```

### Enable external access (LoadBalancer)
```bash
helm install pg ./postgres-cluster \
  -f values-local.yaml \
  --set expose.enabled=true \
  --set expose.type=LoadBalancer
```

### Use existing secret (don't create one)
```bash
helm install pg ./postgres-cluster \
  -f values-local.yaml \
  --set credentials.existingSecret=my-existing-secret
```

---

## Upgrade

```bash
# Change values and upgrade
helm upgrade pg ./postgres-cluster -f values-local.yaml

# Scale instances
helm upgrade pg ./postgres-cluster \
  -f values-local.yaml \
  --set cluster.instances=3
```

## Uninstall

```bash
# Remove chart (keeps PVCs because reclaimPolicy=Retain)
helm uninstall pg

# Also remove PVCs (data deleted!)
kubectl delete pvc --all -n postgres
```

---

## Storage Types

| storageType | Provisioner | Best for |
|---|---|---|
| `local` | rancher.io/local-path | Dev/testing, single node |
| `longhorn` | driver.longhorn.io | Self-managed HA clusters |
| `gke` | pd.csi.storage.gke.io | GKE production |
| `custom` | your own | Any other provisioner |

---

## Connection

After install, the chart prints connection info. Quick reference:

```bash
# Port-forward (primary)
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n postgres

# Port-forward (replicas)
kubectl port-forward svc/postgres-cluster-ro 5433:5432 -n postgres

# Get password
kubectl get secret postgres-cluster-credentials \
  -n postgres \
  -o jsonpath='{.data.password}' | base64 -d && echo ""
```

VS Code settings:
```
Host:     localhost
Port:     5432
Database: app
Username: postgres
SSL Mode: disable
```
