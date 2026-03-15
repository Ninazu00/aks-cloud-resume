# Cloud Resume — AKS Deployment

A full-stack resume site deployed on Azure Kubernetes Service, built as a cloud/cloud security portfolio project. Live at [mohamedayman.work](https://mohamedayman.work).

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
| CI/CD | GitHub Actions |
| Security Scanning | Trivy (image vulnerability scanning) |

---

## Features

- **Visitor counter** — records each visit to PostgreSQL and displays a live count
- **Rate limiting** — per-IP rate limiting on `/api/visit` via `express-rate-limit`
- **HTTPS** — TLS automatically provisioned and renewed by cert-manager
- **3 backend replicas** — load balanced behind the NGINX ingress
- **Readiness probes** — traffic only routed to pods that have connected to the database
- **CI/CD pipeline** — automated build, scan, and deploy on every push to `main`

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

## CI/CD Pipeline

Two GitHub Actions workflows handle the full delivery lifecycle:

**CI** (`.github/workflows/ci.yaml`) — runs on every push to any branch:
- `npm audit` — fails on high/critical dependency vulnerabilities
- `npm ci` — deterministic dependency install
- `npm test` — runs the test suite

**CD** (`.github/workflows/cd.yaml`) — triggers on successful CI run against `main`:
1. Logs into Azure via stored credentials and authenticates to ACR
2. Builds the Docker image tagged with the commit SHA
3. **Trivy scan** — scans the image for HIGH/CRITICAL CVEs; blocks the push if any unfixed vulnerabilities are found
4. Pushes the image to ACR
5. Sets AKS context and updates the `backend` deployment with the new image tag
6. Verifies the rollout completes successfully

The Trivy gate ensures no image with known HIGH or CRITICAL vulnerabilities is ever pushed to the registry or deployed to the cluster.

---

## Security

- Credentials in Kubernetes Secrets, gitignored, never hardcoded
- Non-root container (`USER node` in Dockerfile)
- `npm ci` for deterministic, locked dependency installs
- `npm audit` blocks CI on high/critical dependency vulnerabilities
- Trivy image scan blocks deployment on HIGH/CRITICAL CVEs (unfixed only)
- Rate limiting on write endpoint
- HTTP → HTTPS redirect enforced at ingress

---

## Roadmap

- [x] GitHub Actions CI/CD with security scanning (Trivy)
- [ ] Azure Key Vault via Secrets Store CSI Driver
- [ ] Kubernetes NetworkPolicies
- [ ] Ingress-level rate limiting as a defence-in-depth layer
