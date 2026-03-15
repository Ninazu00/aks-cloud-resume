# Cloud Resume — AKS Deployment

A full-stack resume site deployed on Azure Kubernetes Service, built as a cloud/cloud security portfolio project. Liive at [k8.mohamedayman.work](https://k8.mohamedayman.work/) during testing.

---

## Architecture

```
Internet → Azure Load Balancer → NGINX Ingress (TLS) → Backend Service (ClusterIP)
                                                               │
                                                    Node.js Deployment (3 pods)
                                                               │
                                                    PostgreSQL Service (Headless)
                                                               │
                                                    PostgreSQL StatefulSet
                                                               │
                                                    PersistentVolumeClaim (1Gi)
```

| Layer | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Backend | Node.js, Express |
| Database | PostgreSQL 16 (StatefulSet) |
| Orchestration | Kubernetes (AKS) |
| Ingress | NGINX Ingress Controller |
| TLS | cert-manager + Let's Encrypt |
| Registry | Azure Container Registry |

---

## Features

- **Visitor counter** — records each visit to PostgreSQL and displays a live count
- **Rate limiting** — per-IP rate limiting on `/api/visit` via `express-rate-limit`
- **HTTPS** — TLS automatically provisioned and renewed by cert-manager
- **3 backend replicas** — load balanced behind the NGINX ingress
- **Readiness probes** — traffic only routed to pods that have connected to the database

---

## Key Design Decisions

**Self-managed PostgreSQL over a managed service** — deliberately chosen to demonstrate stateful workload management using StatefulSets and PersistentVolumeClaims rather than offloading to Azure Database or CosmosDB.

**Headless Service for PostgreSQL** — uses `clusterIP: None` to give each pod a stable DNS entry (`postgres-0.postgres.resume.svc.cluster.local`), which is the correct pattern for StatefulSets.

**Secrets never committed** — `k8s/secret.yaml` and `.env` are gitignored. The production path forward is Azure Key Vault via the Secrets Store CSI Driver.

**ConfigMap generated from source** — the postgres init ConfigMap is generated directly from `db/init.sql` via `kubectl create configmap --from-file`, keeping the SQL file as the single source of truth.

---

## Project Structure

```
cloud-aks-resume/
├── backend/
│   ├── server.js           # Express API + static file serving
│   ├── package.json
│   └── Dockerfile
├── frontend/
│   ├── index.html
│   └── js/main.js          # Calls /api/visit, falls back to /api/visits if rate limited
├── db/
│   └── init.sql
├── k8s/
│   ├── namespace.yaml
│   ├── secret.yaml         # Gitignored — not committed
│   ├── configmap.yaml      # Generated from db/init.sql
│   ├── postgres-statefulset.yaml
│   ├── postgres-service.yaml
│   ├── backend-deployment.yaml
│   ├── backend-service.yaml
│   ├── clusterissuer.yaml
│   └── ingress.yaml
└── docker-compose.yaml
```

---

## Local Development

```bash
cp .env.example .env
docker compose up --build
# Available at http://localhost:3001
```

## Minikube

```bash
minikube start
minikube addons enable ingress
minikube docker-env --shell powershell | Invoke-Expression
docker build -t resume-backend:latest .

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml

kubectl create configmap postgres-init \
  --from-file=init.sql=./db/init.sql \
  --namespace=resume \
  --dry-run=client -o yaml > k8s/configmap.yaml
kubectl apply -f k8s/configmap.yaml

kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/ingress.yaml

minikube tunnel
# Available at http://127.0.0.1
```

## AKS

```bash
az group create --name resume-rg --location <region>
az aks create --resource-group resume-rg --name resume-aks \
  --node-count 1 --node-vm-size Standard_B2s_v2 --generate-ssh-keys
az aks get-credentials --resource-group resume-rg --name resume-aks

az acr create --resource-group resume-rg --name <registry-name> --sku Basic
az acr login --name <registry-name>
docker build -t <registry-name>.azurecr.io/resume-backend:latest .
docker push <registry-name>.azurecr.io/resume-backend:latest

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl apply -f k8s/
```

---

## Security

- Credentials in Kubernetes Secrets, gitignored, never hardcoded
- Non-root container (`USER node` in Dockerfile)
- `npm ci` for deterministic, locked dependency installs
- Rate limiting on write endpoint
- HTTP → HTTPS redirect enforced at ingress

---

## Roadmap

- [ ] GitHub Actions CI/CD with OIDC (no stored credentials)
- [ ] Azure Key Vault via Secrets Store CSI Driver
- [ ] Kubernetes NetworkPolicies
- [ ] Ingress-level rate limiting as a defence-in-depth layer
