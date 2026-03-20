# postgres-cluster Helm Chart

PostgreSQL HA Cluster using CloudNativePG. One chart, three storage backends.

![Process of postgres HA Cluster](image.png)

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

## Step 1 — Start port-forwards
 
Open two terminals and keep them running.
 
**Terminal 1 — primary (read-write):**
```bash
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n postgres
```
 
**Terminal 2 — replica (read-only):**
```bash
kubectl port-forward svc/postgres-cluster-ro 5433:5432 -n postgres
```
 
---
 
## Step 2 — Find the primary
 
```bash
kubectl get cluster.postgresql.cnpg.io postgres-cluster \
  -n postgres \
  -o jsonpath='{.status.currentPrimary}' && echo ""
```
 
Or check all pods with their roles:
```bash
kubectl get pods -n postgres -L role
```
 
Or ask PostgreSQL directly (f = primary, t = replica):
```bash
for pod in $(kubectl get pods -n postgres \
  -l cnpg.io/cluster=postgres-cluster \
  -o jsonpath='{.items[*].metadata.name}'); do
  ROLE=$(kubectl exec -n postgres $pod -- \
    psql -U postgres -tAc "SELECT pg_is_in_recovery();" 2>/dev/null)
  echo "$pod → $([ "$ROLE" = "f" ] && echo PRIMARY || echo replica)"
done
```
 
---
 
## Step 3 — Connect and check the primary
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```
 
Expected:
```
 inet_server_addr | pg_is_in_recovery
------------------+-------------------
 10.x.x.x        | f                    ← f = primary ✅
```
 
---
 
## Step 4 — Create test table and insert data
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app << 'EOF'
CREATE TABLE IF NOT EXISTS sync_test (
  id         serial PRIMARY KEY,
  msg        text,
  created_at timestamptz DEFAULT now()
);
 
INSERT INTO sync_test (msg) VALUES
  ('row 1 - first insert'),
  ('row 2 - first insert'),
  ('row 3 - first insert');
 
SELECT * FROM sync_test;
EOF
```
 
Expected:
```
 id |         msg          |          created_at
----+----------------------+-------------------------------
  1 | row 1 - first insert | 2026-03-20 xx:xx:xx+00
  2 | row 2 - first insert | 2026-03-20 xx:xx:xx+00
  3 | row 3 - first insert | 2026-03-20 xx:xx:xx+00
```
 
---
 
## Step 5 — Verify data synced to replica
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5433 -U postgres -d app \
  -c "SELECT * FROM sync_test;"
```
 
Expected — identical rows, instant sync:
```
 id |         msg          |          created_at
----+----------------------+-------------------------------
  1 | row 1 - first insert | 2026-03-20 xx:xx:xx+00
  2 | row 2 - first insert | 2026-03-20 xx:xx:xx+00
  3 | row 3 - first insert | 2026-03-20 xx:xx:xx+00
```
 
---
 
## Step 6 — Confirm replica is read-only
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5433 -U postgres -d app \
  -c "INSERT INTO sync_test (msg) VALUES ('this should fail');"
```
 
Expected:
```
ERROR:  cannot execute INSERT in a read-only transaction
```
 
---
 
## Step 7 — Check replication lag
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "SELECT application_name, state, sent_lsn, replay_lsn, replay_lag
      FROM pg_stat_replication;"
```
 
Expected — lag should be `00:00:00` or empty (real-time):
```
 application_name |   state   | replay_lag
------------------+-----------+------------
 postgres-cluster-2 | streaming | 00:00:00
 postgres-cluster-3 | streaming | 00:00:00
```
 
---
 
## Step 8 — Live sync test
 
Insert on primary and immediately read from replica:
 
```bash
# Insert on primary
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "INSERT INTO sync_test (msg) VALUES ('live sync test - $(date +%T)');"
 
# Read immediately from replica
PGPASSWORD=MyPassword123 psql -h localhost -p 5433 -U postgres -d app \
  -c "SELECT * FROM sync_test ORDER BY id DESC LIMIT 1;"
```
 
The new row should appear on the replica instantly. ✅
 
---
 
## Step 9 — Failover test
 
### 9a — Insert a row before failover
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "INSERT INTO sync_test (msg) VALUES ('inserted BEFORE failover');"
```
 
### 9b — Note current primary
```bash
kubectl get cluster.postgresql.cnpg.io postgres-cluster \
  -n postgres -o jsonpath='{.status.currentPrimary}' && echo ""
```
 
### 9c — Start a connection loop to measure RTO
Open a new terminal and run:
```bash
while true; do
  RESULT=$(PGPASSWORD=MyPassword123 psql \
    -h localhost -p 5432 -U postgres -d app \
    -c "SELECT now()::time(0), inet_server_addr();" \
    -t 2>&1)
  echo "$(date +%H:%M:%S) → $RESULT"
  sleep 1
done
```
 
### 9d — Kill the primary
```bash
PRIMARY=$(kubectl get cluster.postgresql.cnpg.io postgres-cluster \
  -n postgres -o jsonpath='{.status.currentPrimary}')
 
echo "Killing primary: $PRIMARY"
 
kubectl delete pod $PRIMARY -n postgres --force --grace-period=0
```
 
### 9e — Watch failover happen
```bash
watch -n2 "kubectl get pods -n postgres -L role"
```
 
Expected sequence:
```
# Before
postgres-cluster-1   1/1   Running   primary   ← being killed
postgres-cluster-2   1/1   Running   replica
postgres-cluster-3   1/1   Running   replica
 
# During (10-30 seconds)
postgres-cluster-1   0/1   Terminating
postgres-cluster-2   1/1   Running   primary   ← promoted ✅
postgres-cluster-3   1/1   Running   replica
 
# After (pod 1 rejoins)
postgres-cluster-1   1/1   Running   replica   ← back as replica
postgres-cluster-2   1/1   Running   primary
postgres-cluster-3   1/1   Running   replica
```
 
### 9f — Check the connection loop (Terminal from 9c)
You will see a brief error gap — the duration is your RTO:
```
12:00:01 → 10.233.74.112   ← primary responding
12:00:02 → 10.233.74.112
12:00:03 → error            ← failover started
12:00:04 → error
12:00:18 → 10.233.74.89    ← new primary! RTO ≈ 15 seconds ✅
12:00:19 → 10.233.74.89
```
 
### 9g — Verify data survived failover
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "SELECT * FROM sync_test ORDER BY id DESC LIMIT 3;"
```
 
The row inserted before failover must still be there. ✅
 
---
 
## Step 10 — Insert after failover
 
Confirm the new primary accepts writes:
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "INSERT INTO sync_test (msg) VALUES ('inserted AFTER failover');"
 
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "SELECT * FROM sync_test ORDER BY id DESC LIMIT 3;"
```
 
---
 
## Step 11 — Cleanup test data
 
```bash
PGPASSWORD=MyPassword123 psql -h localhost -p 5432 -U postgres -d app \
  -c "DROP TABLE sync_test;"
```