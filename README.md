# Cloud Resume — AKS Deployment

A full-stack resume site deployed on Azure Kubernetes Service, built as a cloud/cloud security portfolio project. Live at [mohamedayman.work](https://mohamedayman.work).

## Architecture

```
Internet → Azure Load Balancer → NGINX Ingress (TLS) → Backend Service
                                                               ↓
                                                     3× Node.js Pods (Deployment)
                                                               ↓
                                                       PostgreSQL Service
                                                               ↓
                                                    PostgreSQL Pod (StatefulSet)
                                                               ↓
                                                    PersistentVolumeClaim (1Gi)
```

## Stack

| Layer | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript |
| Backend | Node.js, Express |
| Database | PostgreSQL 16 (StatefulSet) |
| Container Runtime | Docker |
| Orchestration | Kubernetes (AKS) |
| Ingress | NGINX Ingress Controller |
| TLS | cert-manager + Let's Encrypt |
| Registry | Azure Container Registry (ACR) |
| Cloud | Azure (Azure for Students) |

## Features

- **Visitor counter** — records each visit to the PostgreSQL database and displays a live count
- **Rate limiting** — per-IP rate limiting on the `/api/visit` endpoint via `express-rate-limit`, preventing abuse while keeping the count readable
- **HTTPS** — TLS certificate automatically provisioned and renewed by cert-manager via Let's Encrypt
- **High availability** — 3 backend replicas behind the NGINX ingress load balancer
- **Persistent storage** — PostgreSQL data persists across pod restarts via a PersistentVolumeClaim
- **Readiness probes** — Kubernetes only routes traffic to backend pods that have successfully connected to the database

## Project Structure

```
cloud-aks-resume/
├── backend/
│   ├── server.js          # Express server — visit counter API + static file serving
│   ├── package.json
│   └── Dockerfile
├── frontend/
│   ├── index.html
│   ├── css/styles.css
│   └── js/main.js         # Calls /api/visit on load, falls back to /api/visits if rate limited
├── db/
│   └── init.sql           # Creates visits table (idempotent)
├── k8s/
│   ├── namespace.yaml
│   ├── secret.yaml        # Not committed — contains DB credentials
│   ├── configmap.yaml     # Generated from db/init.sql
│   ├── postgres-statefulset.yaml
│   ├── postgres-service.yaml    # Headless service for stable DNS
│   ├── backend-deployment.yaml  # 3 replicas
│   ├── backend-service.yaml
│   ├── ingress.yaml             # TLS + ssl-redirect
│   └── clusterissuer.yaml       # Let's Encrypt ACME config
├── docker-compose.yaml    # Local development
└── .env                   # Not committed — local secrets
```

## Local Development

**Prerequisites:** Docker Desktop, Node.js

```bash
# Clone the repo
git clone https://github.com/yourusername/cloud-aks-resume.git
cd cloud-aks-resume

# Create .env (see .env.example)
cp .env.example .env

# Start all services
docker compose up --build
```

App will be available at `http://localhost:3001` (or 3002/3003 for other replicas).

## Kubernetes — Local (Minikube)

**Prerequisites:** Minikube, kubectl

```bash
# Start Minikube and enable ingress
minikube start
minikube addons enable ingress

# Build image into Minikube's Docker environment
minikube docker-env --shell powershell | Invoke-Expression
docker build -t resume-backend:latest .

# Create namespace and secrets first
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml        # Create manually — not in repo

# Generate configmap from init.sql
kubectl create configmap postgres-init \
  --from-file=init.sql=./db/init.sql \
  --namespace=resume \
  --dry-run=client -o yaml > k8s/configmap.yaml
kubectl apply -f k8s/configmap.yaml

# Deploy everything else
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/ingress.yaml

# Start tunnel (keep terminal open)
minikube tunnel
```

App will be available at `http://127.0.0.1`.

## Kubernetes — AKS

**Prerequisites:** Azure CLI, kubectl

```bash
# Provision cluster
az group create --name resume-rg --location <allowed-region>
az aks create \
  --resource-group resume-rg \
  --name resume-aks \
  --node-count 1 \
  --node-vm-size Standard_B2s_v2 \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group resume-rg --name resume-aks

# Create ACR and push image
az acr create --resource-group resume-rg --name <registry-name> --sku Basic
az acr login --name <registry-name>
docker build -t <registry-name>.azurecr.io/resume-backend:latest .
docker push <registry-name>.azurecr.io/resume-backend:latest

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Deploy
kubectl apply -f k8s/
```

## Security

- Database credentials stored in Kubernetes Secrets (base64-encoded), never hardcoded in manifests or committed to git
- Non-root container user (`USER node` in Dockerfile)
- Rate limiting at the application layer (1 request/IP/minute on the write endpoint)
- TLS enforced — HTTP automatically redirects to HTTPS via ingress annotation
- `npm ci` used instead of `npm install` for deterministic, locked dependency installs

## Roadmap

- [ ] GitHub Actions CI/CD pipeline with OIDC (no stored credentials)
- [ ] Azure Key Vault via Secrets Store CSI Driver (replace Kubernetes Secrets)
- [ ] Kubernetes NetworkPolicies (restrict pod-to-pod traffic)
- [ ] NGINX ingress rate limiting as defence-in-depth layer
