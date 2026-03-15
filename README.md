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
| Network Security | Kubernetes NetworkPolicies (micro-segmentation) |
| Secrets Management | Azure Key Vault + Secrets Store CSI Driver |

---

## Features

- **Visitor counter** — records each visit to PostgreSQL and displays a live count
- **Rate limiting** — per-IP rate limiting on `/api/visit` via `express-rate-limit` (application layer) and NGINX ingress annotations (network layer)
- **HTTPS** — TLS automatically provisioned and renewed by cert-manager
- **3 backend replicas** — load balanced behind the NGINX ingress
- **Readiness probes** — traffic only routed to pods that have connected to the database
- **CI/CD pipeline** — automated build, scan, and deploy on every push to `main`
- **Network micro-segmentation** — NetworkPolicies enforce least-privilege pod-to-pod communication
- **Zero-credential secrets** — Azure Key Vault secrets injected at pod startup via the Secrets Store CSI Driver using federated identity — no passwords stored anywhere

---

## Key Design Decisions

**Self-managed PostgreSQL over a managed service** — deliberately chosen to demonstrate stateful workload management using StatefulSets and PersistentVolumeClaims rather than offloading to Azure Database or CosmosDB.

**Headless Service for PostgreSQL** — uses `clusterIP: None` to give each pod a stable DNS entry (`postgres-0.postgres.resume.svc.cluster.local`), which is the correct pattern for StatefulSets.

**Secrets managed by Azure Key Vault via Secrets Store CSI Driver** — no credentials are stored in the cluster. The CSI driver authenticates to Key Vault using a managed identity and federated identity credentials (OIDC) — no passwords or client secrets anywhere in the chain. At pod startup the driver fetches secrets from Key Vault and mounts them as an ephemeral volume, which Kubernetes then surfaces as environment variables. The `secret.yaml` file is gitignored and no longer needed for production.

**Network micro-segmentation via NetworkPolicies** — a `deny-all` default policy blocks all pod-to-pod traffic in the `resume` namespace. Explicit allow policies then permit only the necessary paths: ingress controller → backend (ingress), backend → postgres on port 5432 (egress), and backend → kube-dns on UDP 53 for service discovery. This enforces least-privilege at the network layer — a compromised backend pod cannot reach anything beyond postgres. **Note that the network policy enforcer (Azure or Calico) must be explicitly stated during cluster creation. This cost me a lot of time!**

**Ingress-level rate limiting as defence-in-depth** — NGINX ingress annotations rate limit `/api` endpoints (5 req/s, burst of 15) independently of the application-layer `express-rate-limit`. Static assets are intentionally excluded to avoid blocking legitimate page loads. Two independent rate limiting layers mean the API is protected even if one layer is bypassed or fails.

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
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   └── secretproviderclass.yaml
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

## Secrets Management

Secrets are stored in Azure Key Vault and injected into pods at startup via the Secrets Store CSI Driver — no credentials are stored in the cluster at any point.

**How it works:** The CSI driver runs as a daemonset on every node. When a pod starts, the driver authenticates to Azure Key Vault using a managed identity, fetches the specified secrets, and mounts them into the pod as an ephemeral volume. A `SecretProviderClass` resource defines which vault, which secrets, and which identity to use. The secrets are also surfaced as a Kubernetes Secret object, allowing pods to consume them as standard environment variables.

**Authentication — federated identity (OIDC):** The managed identity never uses a password. Instead, the driver presents a Kubernetes service account token to Azure AD. Azure validates the token against registered federated identity credentials — trust relationships that say "accept tokens from this cluster issuer, for this service account." If the token matches, Azure issues an access token. No secret ever exists in the chain.

**`SecretProviderClass`** (`k8s/secretproviderclass.yaml`) — references the Key Vault name, managed identity client ID, tenant ID, and the list of secrets to fetch. Also defines a `secretObjects` block that maps Key Vault secret names to Kubernetes Secret keys, keeping the pod's env var references unchanged.

---

## Network Security

Three NetworkPolicies enforce micro-segmentation across the `resume` namespace:

**`deny-all`** — selects all pods with an empty `podSelector: {}` and declares both `Ingress` and `Egress` policy types with no rules. This is the default-deny baseline — nothing is permitted unless an explicit allow policy exists.

**`allow-backend`** — applied to `app: backend` pods:
- Ingress: permits traffic from the `ingress-nginx` namespace only (the NGINX ingress controller)
- Egress: permits TCP 5432 to `app: postgres` pods, and UDP 53 to `kube-system` for DNS resolution

**`allow-postgres`** — applied to `app: postgres` pods:
- Ingress: permits TCP 5432 from `app: backend` pods only
- No egress policy declared — response traffic is automatically permitted as it is stateful (connection tracking handles replies)

The result: a compromised backend pod can reach postgres and nothing else. A compromised postgres pod cannot initiate any connections at all.

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

- Secrets sourced from Azure Key Vault via Secrets Store CSI Driver — never stored in the cluster
- Federated identity (OIDC) for Key Vault authentication — no client secrets or passwords
- Non-root container (`USER node` in Dockerfile)
- `npm ci` for deterministic, locked dependency installs
- `npm audit` blocks CI on high/critical dependency vulnerabilities
- Trivy image scan blocks deployment on HIGH/CRITICAL CVEs (unfixed only)
- Rate limiting on `/api` at both application layer (`express-rate-limit`) and network layer (NGINX ingress annotations)
- NetworkPolicies enforce default-deny with least-privilege allow rules per pod
- HTTP → HTTPS redirect enforced at ingress

---

## Roadmap

- [x] GitHub Actions CI/CD with security scanning (Trivy)
- [x] Azure Key Vault via Secrets Store CSI Driver
- [x] Kubernetes NetworkPolicies
- [x] Ingress-level rate limiting as a defence-in-depth layer
