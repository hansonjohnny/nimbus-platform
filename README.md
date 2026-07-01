# Nimbus Retail Platform - Infrastructure & Deployment

Production-grade infrastructure for the Nimbus Retail microservices platform. Built on AWS EKS with Terraform, managed via ArgoCD GitOps, and automated through Jenkins CI/CD.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [AWS Infrastructure](#aws-infrastructure)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Helm Charts](#helm-charts)
- [Kafka/Strimzi](#kafkastrimzi)
- [ArgoCD GitOps](#argocd-gitops)
- [Jenkins CI/CD Pipeline](#jenkins-cicd-pipeline)
- [Quick Start](#quick-start)
- [Development Workflow](#development-workflow)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS Account (us-east-2)                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │   VPC (10.0/16)  │  │  Jenkins Server  │                │
│  │                  │  │  (EC2 + EIP)     │                │
│  │  ┌────────────┐  │  │                  │                │
│  │  │  EKS Cluster   │  │  CI/CD Pipeline  │                │
│  │  │ (1 node)   │  │  └──────────────────┘                │
│  │  │            │  │                                       │
│  │  │ ┌────────────────────────────────────┐              │
│  │  │ │   K8s Namespaces                   │              │
│  │  │ │  ┌─────────────────────────────┐   │              │
│  │  │ │  │  nimbus-prod                │   │              │
│  │  │ │  │ • 6 microservices           │   │              │
│  │  │ │  │ • HPA enabled (1-3 replicas)│   │              │
│  │  │ │  │ • Kafka consumers/producers │   │              │
│  │  │ │  └─────────────────────────────┘   │              │
│  │  │ │  ┌─────────────────────────────┐   │              │
│  │  │ │  │  argocd                     │   │              │
│  │  │ │  │ • GitOps controller         │   │              │
│  │  │ │  └─────────────────────────────┘   │              │
│  │  │ │  ┌─────────────────────────────┐   │              │
│  │  │ │  │  strimzi-system             │   │              │
│  │  │ │  │ • Kafka operator            │   │              │
│  │  │ │  │ • Kraft mode (no ZK)        │   │              │
│  │  │ │  └─────────────────────────────┘   │              │
│  │  │ └────────────────────────────────────┘              │
│  │  └────────────┘  │                                      │
│  │                  │                                      │
│  │  ┌────────────┐  │  ┌───────────────────┐              │
│  │  │ RDS        │  │  │ ElastiCache Redis │              │
│  │  │ PostgreSQL │  │  │ 7.1 (encrypted)   │              │
│  │  │ 16         │  │  │ cluster.t3.micro  │              │
│  │  │ Multi-AZ   │  │  └───────────────────┘              │
│  │  │ gp3        │  │                                      │
│  │  └────────────┘  │                                      │
│  └──────────────────┘                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## AWS Infrastructure

### Database: RDS PostgreSQL

```hcl
# Configuration
- Engine: PostgreSQL 16
- Instance class: db.t3.micro (free tier)
- Storage: 20GB (gp3)
- Multi-AZ: Yes (production-ready)
- Backup retention: 0 days (free tier)
- Encryption: At-rest (KMS)
- Performance Insights: Enabled
- Endpoint: Auto-generated, retrieved via Terraform outputs
```

**Access from EKS:**

- Security group allows port 5432 from EKS node group security group
- Connection string format: `postgresql://nimbus_admin:${DB_PASSWORD}@${RDS_ENDPOINT}:5432/nimbus`

### Cache: ElastiCache Redis

```hcl
# Configuration
- Engine: Redis 7.1
- Node type: cache.t3.micro (free tier)
- Encryption at rest: Enabled (default.redis7 parameter group)
- Cluster mode: Disabled (single node)
- Multi-AZ: No (single node only)
- Endpoint: Auto-generated, retrieved via Terraform outputs
```

**Access from EKS:**

- Security group allows port 6379 from EKS node group security group
- Connection string format: `redis://${REDIS_ENDPOINT}:6379`

### Network: VPC & Security Groups

```
VPC: 10.0.0.0/16
├─ Public Subnets: 10.0.1.0/24, 10.0.2.0/24 (Jenkins, NAT Gateways)
├─ Private Subnets: 10.0.10.0/24, 10.0.11.0/24 (EKS, RDS, Redis)
└─ Security Groups:
   ├─ EKS Cluster SG: Allows 443 (API)
   ├─ EKS Nodes SG: Allows kubelet (10250) + pod traffic (1025-65535)
   ├─ Jenkins SG: Allows 8080, 50000 from anywhere (SSH access for git)
   ├─ RDS SG: Allows 5432 from EKS Nodes SG
   └─ Redis SG: Allows 6379 from EKS Nodes SG
```

---

## Kubernetes Deployment

### EKS Cluster

```hcl
# Configuration
- Version: Latest available (auto-determined)
- Node group: 1 node (t3.medium)
- AMI: EKS-optimized Amazon Linux 2
- Role: Custom IAM with EKS permissions
- OIDC provider: Enabled for IRSA (not currently used)
- Endpoint: Public (restricted by security groups)
- Logging: Disabled (reduce costs)
```

### Namespaces

| Namespace                                       | Purpose                               | Managed By       |
| ----------------------------------------------- | ------------------------------------- | ---------------- |
| `nimbus-prod`                                   | Production microservices (6 services) | ArgoCD           |
| `argocd`                                        | ArgoCD controller & UI                | Helm (Terraform) |
| `strimzi-system`                                | Kafka operator                        | Helm (Terraform) |
| `default`                                       | Kubernetes system                     | N/A              |
| `kube-system`, `kube-node-lease`, `kube-public` | K8s internals                         | N/A              |

---

## Helm Charts

### Chart Structure

Each microservice has an **independent Helm chart** in `helm/${SERVICE_NAME}/`:

```
helm/
├── auth-service/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── hpa.yaml (Horizontal Pod Autoscaler)
│       └── _helpers.tpl
├── catalog-service/
├── cart-service/
├── order-service/
├── notification-service/
└── frontend/
```

### Common Configuration

All charts follow this pattern:

```yaml
# values.yaml
image:
  repository: "943378954775.dkr.ecr.us-east-2.amazonaws.com/nimbus-retail/SERVICE_NAME"
  tag: "latest" # Updated by Jenkins on each build

service:
  type: ClusterIP
  port: SERVICE_PORT

hpa:
  enabled: true
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70

# Service-specific env vars baked into deployment.yaml
kafka:
  brokers: "nimbus-kafka-kafka-bootstrap.nimbus-prod.svc.cluster.local:9092"
```

### Services & Ports

| Service                  | Port | Database    | Redis | Kafka               | Notes                        |
| ------------------------ | ---- | ----------- | ----- | ------------------- | ---------------------------- |
| **auth-service**         | 3001 | ✓ (auth)    | ✗     | ✓ (produce events)  | JWT auth provider            |
| **catalog-service**      | 3002 | ✓ (catalog) | ✓     | ✗                   | Product metadata + cache     |
| **cart-service**         | 3003 | ✓ (cart)    | ✓     | ✗                   | Shopping cart with Redis     |
| **order-service**        | 3004 | ✓ (orders)  | ✗     | ✓ (consume/produce) | Order processing             |
| **notification-service** | 3005 | ✗           | ✗     | ✓ (consume)         | Email/SMS notifications      |
| **frontend**             | 80   | ✗           | ✗     | ✗                   | Nginx static + reverse proxy |

### Environment Variables

**Database Connection:**

- Source: K8s Secrets (`auth-service-secrets`, `catalog-service-secrets`, etc.)
- Key: `DATABASE_URL`
- Format: `postgresql://user:pass@rds-endpoint:5432/dbname`

**Redis Connection:**

- Source: K8s Secrets (`catalog-service-secrets`, `cart-service-secrets`)
- Key: `REDIS_URL`
- Format: `redis://redis-endpoint:6379`

**Kafka Brokers:**

- Source: `values.yaml` (hardcoded to Strimzi bootstrap address)
- Key: `KAFKA_BROKERS`
- Value: `nimbus-kafka-kafka-bootstrap.nimbus-prod.svc.cluster.local:9092`

**JWT Secret:**

- Source: K8s Secrets (`jwt-secret`)
- Used by: auth-service (sign), cart-service, order-service (verify)

---

## Kafka/Strimzi

### Operator Installation

- **Helm Release**: `strimzi-cluster-operator` (v0.43.0)
- **Namespace**: `strimzi-system`
- **Watch Scope**: `nimbus-prod` namespace only

### Kafka Cluster Configuration

**KafkaNodePool** (`kafka-cluster.yaml`):

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: persistent-claim
    size: 10Gi
```

**Kafka CR** (`kafka-cluster.yaml`):

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: nimbus-kafka
spec:
  kafka:
    version: 3.8.0
    metadataVersion: 3.8-IV0
    config:
      auto.create.topics: "false"
      # KRaft mode (no ZooKeeper)
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
  # No ZooKeeper in KRaft mode
  entityOperator:
    topicOperator: {}
```

### Kafka Topics

**Topic: `orders.created`**

- Partitions: 1
- Replicas: 1
- Retention: 7 days
- Schema: [orders.created.v1.json](../nimbus-retail-starter2/schemas/orders.created.v1.json)
- Producers: order-service
- Consumers: notification-service

**Topic: `users.registered`**

- Partitions: 1
- Replicas: 1
- Retention: 7 days
- Schema: [users.registered.v1.json](../nimbus-retail-starter2/schemas/users.registered.v1.json)
- Producers: auth-service
- Consumers: notification-service

---

## ArgoCD GitOps

### Installation

- **Helm Release**: `argo-cd` (v7.3.4, official ArgoCD Helm chart)
- **Namespace**: `argocd`
- **Service Type**: `ClusterIP` (access via `kubectl port-forward`)

### Repository Configuration

ArgoCD is configured to sync the `nimbus-platform` Git repository:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nimbus-retail-production
spec:
  project: default
  source:
    repoURL: https://github.com/hansonjohnny/nimbus-platform
    targetRevision: main
    path: helm/
  destination:
    server: https://kubernetes.default.svc
    namespace: nimbus-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Note:** ArgoCD Application CR is not yet created in this setup. It will be added in the next phase.

### Access ArgoCD UI

```bash
# Port-forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Retrieve initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Access UI at https://localhost:8080
```

---

## Jenkins CI/CD Pipeline

### Overview

Jenkins automates:

1. **Detect Changes**: Identify which services changed in the commit
2. **Build Images**: Docker build and push to ECR
3. **Security Scans**: OWASP, SonarQube, Trivy
4. **Update Helm Values**: Update image tag in `helm/${SERVICE}/values.yaml`
5. **Push to Nimbus-Platform Repo**: Commit and push, triggering ArgoCD sync

### Shared Library

Located in: [jenkins-shared-library](../jenkins-shared-library/)

**Reusable Steps:**

- `detectChangedService()` - Identify changed services
- `dockerBuild()` - Build and tag Docker image
- `ecrPush()` - Push image to AWS ECR
- `sonarAnalysis()` - Run SonarQube analysis
- `owaspScan()` - OWASP dependency check
- `trivyScan()` - Trivy image vulnerability scan
- `updateK8sDeployment()` - Update Helm chart values
- `frontendPipeline()` - Special pipeline for frontend

### Deployment Flow

```
GitHub Push (Webhook)
    ↓
Jenkins Pipeline Triggered
    ├─ Detect Changed Services
    ├─ For Each Service:
    │  ├─ Docker Build → ECR Push
    │  ├─ OWASP Scan
    │  ├─ SonarQube Analysis
    │  ├─ Trivy Image Scan
    │  └─ Update helm/${SERVICE}/values.yaml
    ├─ Commit & Push to nimbus-platform/main
    ↓
ArgoCD Detects Changes
    ├─ Sync helm/ → EKS
    └─ Deploy New Images

Pods Updated (Rolling Restart)
    ↓
Deployment Complete
```

### Image Tag Strategy

Jenkins uses the **build number** as the Docker image tag:

```bash
# In updateK8sDeployment.groovy
sed -i 's|tag:.*|tag: "${BUILD_NUMBER}"|' helm/${service}/values.yaml
```

Example: Build #42 produces image tag `42`

**Full ECR URL:**

```
943378954775.dkr.ecr.us-east-2.amazonaws.com/nimbus-retail/auth-service:42
```

### Jenkins Configuration

**Environment:**

- Jenkins Server: EC2 (t3.micro)
- IAM Role: Allows ECR push, S3 read, EKS describe
- Webhook: GitHub→Jenkins on main branch push
- Shared Library Folder: `jenkins-shared-library` (GitHub)

---

## Terraform File Reference

### Core Files

| File           | Purpose                                                |
| -------------- | ------------------------------------------------------ |
| `providers.tf` | AWS, Kubernetes, Helm, TLS providers                   |
| `backend.tf`   | Terraform state backend (local for now)                |
| `variables.tf` | Input variables with defaults                          |
| `outputs.tf`   | Terraform outputs (RDS endpoint, Redis endpoint, etc.) |

### AWS Infrastructure

| File              | Purpose                                        |
| ----------------- | ---------------------------------------------- |
| `vpc.tf`          | VPC, subnets, NAT, internet gateway            |
| `sg.tf`           | All security groups (EKS, Jenkins, RDS, Redis) |
| `iam-roles.tf`    | IAM roles for EKS, EC2, ArgoCD (IRSA)          |
| `iam-policies.tf` | IAM policies attached to roles                 |
| `ec2.tf`          | Jenkins server (EC2, EIP)                      |
| `rds.tf`          | PostgreSQL 16 (Multi-AZ, encrypted)            |
| `elasticache.tf`  | Redis 7.1 cluster (encrypted)                  |
| `ecr.tf`          | ECR repositories for 6 services                |
| `eks.tf`          | EKS cluster, node group, OIDC provider         |

### Kubernetes & Helm

| File        | Purpose                                                  |
| ----------- | -------------------------------------------------------- |
| `argocd.tf` | ArgoCD & Strimzi Kafka operator (Helm releases)          |
| `helm/`     | 6 independent Helm charts + frontend                     |
| `kafka/`    | Strimzi Kafka cluster CRs (KafkaNodePool, Kafka, Topics) |

---

## Quick Start

### Prerequisites

```bash
# Install tools
- Terraform >= 1.5.0
- AWS CLI v2 (configured with credentials)
- kubectl >= 1.24
- Helm >= 3.0
- Docker (for building images)
```

### Deploy Infrastructure

```bash
cd nimbus-platform/Terraform-Files

# Initialize Terraform (downloads providers)
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output

# Get RDS password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id nimbus-retail/dev/db-password \
  --region us-east-2 --query SecretString --output text
```

### Access Kubernetes

```bash
# Configure kubectl
aws eks update-kubeconfig --name nimbus-retail-eks --region us-east-2

# Verify cluster
kubectl get nodes

# Check services
kubectl get svc -n nimbus-prod
```

### Deploy Services via ArgoCD

```bash
# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login
# Username: admin
# Password: $(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)

# Create Application CR (TODO: add to argocd.tf)
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nimbus-retail-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/hansonjohnny/nimbus-platform
    targetRevision: main
    path: helm/
  destination:
    server: https://kubernetes.default.svc
    namespace: nimbus-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Trigger sync manually
argocd app sync nimbus-retail-production
```

### View Logs

```bash
# Pod logs
kubectl logs -n nimbus-prod -l app=auth-service

# Stream logs
kubectl logs -n nimbus-prod -l app=auth-service -f

# Multiple containers
kubectl logs -n nimbus-prod -l app=auth-service --all-containers=true
```

---

## Development Workflow

### Adding a New Service

1. **Create Docker image** in nimbus-retail-starter2/services/
2. **Create Helm chart** in nimbus-platform/helm/new-service/
3. **Update Terraform**:
   - Add ECR repository to `ecr.tf`
   - Add service values to `terraform.tfvars`
4. **Push to GitHub** → Triggers Jenkins pipeline
5. **ArgoCD syncs** new Helm chart → K8s deployment

### Updating a Service

1. **Modify code** in nimbus-retail-starter2/services/
2. **Push to GitHub** → Jenkins webhook triggered
3. **Jenkins pipeline**:
   - Detects changed service
   - Builds Docker image → ECR (tag = build number)
   - Updates `helm/SERVICE_NAME/values.yaml`
   - Commits & pushes to nimbus-platform
4. **ArgoCD detects change** → Syncs helm/ → K8s
5. **Pods restart** with new image

### Emergency Rollback

```bash
# Via ArgoCD UI
# Application → History → Select previous sync → Sync

# Via kubectl
kubectl rollout history deployment/auth-service -n nimbus-prod
kubectl rollout undo deployment/auth-service -n nimbus-prod --to-revision=2

# Via Helm
helm rollback auth-service 1 -n nimbus-prod
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n nimbus-prod -o wide

# Describe pod for events
kubectl describe pod POD_NAME -n nimbus-prod

# View logs
kubectl logs POD_NAME -n nimbus-prod --previous  # if crashed
```

### Database Connection Issues

```bash
# Test RDS connectivity from pod
kubectl run -it --rm debug --image=postgres:16 --restart=Never \
  -n nimbus-prod -- \
  psql -h RDS_ENDPOINT -U nimbus_admin -d nimbus

# Get RDS endpoint
terraform output -raw rds_endpoint
```

### Redis Connection Issues

```bash
# Test Redis connectivity from pod
kubectl run -it --rm debug --image=redis:7 --restart=Never \
  -n nimbus-prod -- \
  redis-cli -h REDIS_ENDPOINT ping

# Get Redis endpoint
terraform output -raw redis_endpoint
```

### Kafka Topics Not Available

```bash
# List topics
kubectl exec -it nimbus-kafka-kafka-0 -n nimbus-prod -- \
  bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Describe topic
kubectl exec -it nimbus-kafka-kafka-0 -n nimbus-prod -- \
  bin/kafka-topics.sh --describe --topic orders.created --bootstrap-server localhost:9092
```

### ArgoCD Sync Issues

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Get Application status
kubectl get application -n argocd -o wide

# Manually sync
argocd app sync APPNAME --prune
```

---

## Security Notes

- **Database Password**: Stored in AWS Secrets Manager (`nimbus-retail/dev/db-password`)
- **Redis Encryption**: At-rest encryption enabled (AWS-managed keys)
- **RDS Encryption**: At-rest encryption enabled (AWS-managed keys)
- **IAM Roles**: Least-privilege for EKS nodes, Jenkins EC2, ArgoCD
- **Network Security**: RDS/Redis in private subnets, accessible only from EKS nodes
- **SSL/TLS**: Kubernetes provider uses TLS for EKS API (auto-managed)

---

## Costs & Free Tier

### Free Tier Eligible (12 months)

- **RDS**: db.t3.micro (20GB, 0 backup retention = $0/month)
- **ElastiCache**: cache.t3.micro ($0.017/hour ≈ $12/month)
- **EKS**: t3.medium node ($0.0416/hour ≈ $30/month)
- **EC2**: t3.micro Jenkins ($0.0116/hour ≈ $8.50/month)

### Not Free

- **Data Transfer**: Cross-AZ traffic, NAT gateway ($0.045/GB)
- **EBS**: Root volume storage (~$2-5/month)
- **ECR**: Image storage (~$0.10/GB per month)

**Estimated Monthly Cost**: $50-100 (within free tier budget)

---

## Useful Commands

```bash
# Terraform
terraform init
terraform plan
terraform apply
terraform destroy
terraform output
terraform output -raw rds_endpoint

# Kubectl
kubectl get all -n nimbus-prod
kubectl describe deployment auth-service -n nimbus-prod
kubectl exec -it POD -n nimbus-prod -- /bin/sh
kubectl port-forward svc/auth-service 3001:3001 -n nimbus-prod

# Helm
helm list -n nimbus-prod
helm get values auth-service -n nimbus-prod
helm upgrade auth-service ./helm/auth-service -n nimbus-prod

# ArgoCD
argocd app list
argocd app status APPNAME
argocd app sync APPNAME

# AWS
aws eks update-kubeconfig --name nimbus-retail-eks --region us-east-2
aws ecr describe-repositories --region us-east-2
aws secretsmanager list-secrets --region us-east-2
```

---

## Files Modified This Session

- ✅ `providers.tf` - Fixed module.eks → aws_eks_cluster.main references
- ✅ `argocd.tf` - Fixed depends_on = [module.eks] → [aws_eks_node_group.main]
- ✅ `backend.tf` - Switched to local backend (S3 backend pending)
- ✅ `jenkins-shared-library/vars/updateK8sDeployment.groovy` - Updated path to helm/${service}/values.yaml

---

## Next Steps

1. **Push to GitHub**: Commit all Terraform changes and push to nimbus-platform main
2. **Create ArgoCD Application CR**: Add to argocd.tf or create manually via kubectl
3. **Test End-to-End**: Push a service change → Jenkins → ArgoCD → K8s deployment
4. **Configure S3 Backend**: Create S3 bucket + DynamoDB table, migrate Terraform state
5. **Add Monitoring**: Prometheus, Grafana, or CloudWatch for observability
6. **Add Ingress**: API Gateway or Nginx Ingress for external access
