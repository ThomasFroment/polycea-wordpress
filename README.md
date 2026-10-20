# Polycea WordPress

Déploiement d'un WordPress sur un cluster Kubernetes, dans le cadre d'un exercice technique Polycea.

# Structure

```bash
└── polycea-wordpress/
    ├── .github/
    │   └── workflows/         # Pipelines CI/CD (Terraform apply, Helm install, lint)
    ├── helm/
    │   └── wordpress/         # Chart Helm wordpress (Deployments, Services, PVC)
    │       ├── templates/
    │       ├── Chart.yaml
    │       └── values.yaml
    └── terraform/
        ├── bootstrap/         # Infrastructure bootstrap (S3, OIDC pour GitHub Actions)
        │   └── env/           # Fichier .tfvars commun pour les environnements
        └── infra/             # Infrastructure coeur (VPC, EKS, RDS, EFS, K8S, SG)
            └── env/           # Fichiers .tfvars par environnement (`dev`, `prod`)
```

> [!CAUTION]
> Par souci de simplicité, la StorageClass, le namespace et les secrets k8s sont gérés dans la stack `infra`. Toutefois ce couplage peut créer des problèmes de dépendance, notamment des blocages lors du destroy.

> [!IMPORTANT]
> La stack `bootstrap` existe car la stack `infra` a besoin du bucket S3 (state distant) et du fournisseur OIDC avant de pouvoir être déployée.

# Architecture

<img width="1720" height="1500" alt="aws_simplified_architecture" src="https://github.com/user-attachments/assets/1ba02b7b-426c-4e4f-9dde-8f1bc4abdb97" />

Ci-dessous une description de l'architecture du projet. Beaucoup de valeurs (e.g. nombre de sous-réseaux, ...) sont des valeurs par défaut de Terraform et peuvent être configurées dans un fichier `.tfvars`.

## Réseau

Le réseau repose sur 1 VPC réparti sur 2 zones de disponibilité (AZ) sur la région `eu-west-3` :

- **2 sous-réseaux publics** : disposent d'une route vers l'Internet Gateway. Ils accueillent les NAT Gateways + Elastic IP. Kubernetes y déploie automatiquement les Load Balancers.
- **2 sous-réseaux privés** : hébergent les worker nodes ainsi que la base RDS et les points de montage NFS (EFS). Les sous-réseaux privés disposent d'une route vers une NAT Gateway pour les flux sortants.

> [!NOTE]
> Dans un environnement `prod-ready` on aurait privilégié une architecture 3-tiers comme le recommande la documentation AWS. Avec deux sous-réseaux `isolated`/`data` sans route vers Internet pour les BDD RDS et les points de montage EFS.

## EKS

Le cluster Kubernetes est managé par AWS EKS, on délègue à AWS la responsabilité des mises à jour, backups `etcd`, patch de sécurité et la haute disponibilité (EKS est multi-az). Les worker nodes sont déployés sur les sous-réseaux privés (distribués entre eux).

EKS déploie automatiquement les Load Balancers pour les services K8S (si `type: LoadBalancer`), EKS identifie les sous-réseaux valides à travers un tag.

> [!TIP]
> Aucun mécanisme d'autoscaling (e.g. Karpenter) n'étant installé sur le cluster, la taille du node group est fixe (`min`, `max` et `desired` sont identiques).
> Les pods sont répartis entre les AZ via `topology.kubernetes.io/zone`. La contrainte est en `ScheduleAnyway`.

> [!TIP]
> Le service WordPress est exposé via un Load Balancer (NLB) créé par `type: LoadBalancer` (in-tree controller). Dans le scope de ce projet, ce choix me paraissait suffisant et évite d'installer et de configurer un contrôleur supplémentaire (+ IAM). Le compromis est l'absence de routage L7 et de terminaison TLS, qui nécessiteraient un nom de domaine et un ALB (AWS Load Balancer Controller).

> [!CAUTION]
> L'endpoint de l'API EKS est public (`0.0.0.0/0`). Les runners GitHub hébergés ont des IP changeantes, il n'est donc pas possible de restreindre l'accès à une liste de CIDR fixe.
> Une alternative `prod-ready` serait un runner self-hosted dans le VPC avec l'endpoint public désactivé, ou alors des accès VPN dans le VPC.

### Addons EKS

- **VPC CNI** (addon par défaut géré par AWS) : Attribue aux pods des adresses IP issues des sous-réseaux privés du VPC.
- **EFS CSI Driver** : Permet au cluster de communiquer avec EFS et de monter dynamiquement les volumes NFS partagés dans les pods.
- **EKS Pod Identity Agent** : Permet de délivrer des identifiants IAM aux pods pour leur permettre l'accès à des ressources AWS (e.g. CSI Driver)

## Stockage

- **AWS RDS (MySQL)** : Déployé dans les sous-réseaux privés
- **AWS EFS** : Système de fichiers partagé distribué sur les deux AZ. Il permet le partage des fichiers WordPress (`wp-content`) entre les multiples réplicas de pods (`ReadWriteMany` / `RWX`).

> [!TIP]
> EFS a été choisi pour obtenir du `RWX` avec plusieurs réplicas. Le volume contient actuellement tout le dossier `wp-content`, y compris le code PHP (plugins, thèmes) et pas seulement les uploads. Une image Docker avec plugins/thèmes baked-in et un montage limité à `uploads` serait plus propre.

> [!NOTE]
> La taille déclarée dans le PVC (`storage: 10Gi`) est obligatoire pour satisfaire l'API Kubernetes mais entièrement ignorée par le driver EFS CSI. EFS étant un système de fichiers élastique.

> [!WARNING]
> RDS (port 3306) et EFS (port 2049) acceptent les connexions depuis le Security Group partagé par les worker nodes et le control plane EKS.

# Helm

- **Image** : `bitnami/wordpress` épinglée par digest SHA256.
- **Sécurité** : non-root, `allowPrivilegeEscalation: false`, `drop: ALL`, seccomp `RuntimeDefault`.
- **Probes** : readiness sur `/wp-login.php`, liveness sur `/license.txt` (fichier statique léger).
- **Ressources** : `requests` et `limits` définies.
- **Persistance** : PVC en `ReadWriteMany` sur la StorageClass EFS, pour partager les fichiers WordPress entre les réplicas.

> [!WARNING]
> `bitnami/wordpress` a été préférée à l'image officielle car elle tourne nativement en non-root et tolère la suppression complète des caps Linux.

> [!CAUTION]
> Les identifiants MySQL et WordPress sont générés par Terraform (`random_password`) et stockés dans des `Secret` Kubernetes (base64). Ils sont aussi présents dans le state Terraform.
> En `prod-ready` la stack AWS Secrets Manager + KMS + ESO (External Secrets Operator).

# CI/CD

L'authentification auprès d'AWS s'effectue via une fédération d'identité OIDC entre GitHub et AWS IAM. 
Deux rôles AWS sont utilisés pour ce pipeline :

- `github-oidc-role-terraform-poly-wp` : Provisionné par la stack `bootstrap`. Il accorde à Terraform la policy `AdministratorAccess` sur le compte AWS.
- `github-oidc-role-helm-poly-wp` : Provisionné par la stack `infra`. Il accorde au workflow Helm l'action AWS `eks:DescribeCluster` et associe l'access entry EKS `AmazonEKSEditPolicy` restreinte au namespace `polycea-wordpress`.

La chaîne se compose de 4 pipelines :

- `terraform-lint.yml` : Linting et vérification de formatage à chaque PR ou push.
- `terraform-apply.yml` : Déploiement de l'infrastructure avec sélection manuelle de l'environnement.
- `helm-lint.yml` : Linting du chart (`helm lint`) à chaque PR ou push.
- `helm-install.yml` : Déploiement de la release Helm sur le cluster EKS cible.

> [!WARNING]
> Ce pipeline n'est pas `prod-ready` :
> - Le rôle Terraform utilise `AdministratorAccess`. En production, il faudrait le restreindre aux seules ressources du projet.
> - Aucun scan de sécurité n'est exécuté dans les pipelines (e.g. Trivy, Checkov).
> - Le job `apply` recalcule le plan au lieu d'appliquer celui affiché dans le job `plan`.
> - Le déploiement Terraform reste manuel (`workflow_dispatch`) pour éviter des `apply` non intentionnels (coûts).

> [!NOTE]
> Le job `terraform-apply` utilise un `environment` GitHub uniquement pour permettre une approbation manuelle avant l'`apply`. Les secrets (`AWS_ROLE_ARN`, `EKS_ADMIN_ROLE_ARN`) sont définis au niveau du dépôt et sont donc partagés entre `dev` et `prod`.

> [!IMPORTANT]
> La condition OIDC des rôles (`sub`) est restreinte au dépôt mais accepte toutes les branches (`:*`). C'est un choix volontaire pour pouvoir lancer la CI/CD depuis des branches de développement. En `prod-ready`, on restreindrait le `sub` à une branche protégée ou à un `environment` GitHub (e.g. `environment:prod`).

# Environnements

Le projet fonctionne autour de deux environnements : `dev` et `prod`. L'objectif est de réduire les coûts et le temps de déploiement en développement.

- **NAT Gateway** : 1 seule NAT Gateway en `dev` pour tous les sous-réseaux privés (contre 1 par AZ en `prod` pour la haute disponibilité).
- **RDS** : Déployé en Single-AZ en `dev` et Multi-AZ en `prod`. `skip_final_snapshot: true` en `dev` réduit le temps nécessaire à la destruction. Le stockage est chiffré et la rétention des sauvegardes est configurable. Les mises à jour utilisent le mécanisme Blue/Green de RDS uniquement en `prod` (nécessite Multi-AZ).

Actuellement, la séparation repose sur :

- Un compte AWS unique, différenciation par tags.
- Deux workspaces Terraform pour séparer les `.tfstate`, avec des fichiers `.tfvars` distincts.
- Un choix d'environnement au lancement du workflow CI/CD.

> [!WARNING]
> Cette séparation n'est pas `prod-ready` :
> - Pas de frontière de sécurité étanche entre `dev` et `prod`. En `prod-ready`, on utiliserait des comptes AWS dédiés via AWS Organizations.
> - Les workspaces sont déconseillés par HashiCorp pour isoler des environnements. On préférerait des répertoires/modules dédiés avec des backends S3 distincts.

# Déploiement

### Prérequis

- Terraform `>= 1.16.0`
- Helm `>= 4.3`
- AWS CLI
- `kubectl`

### 1. Bootstrap

Initialise le bucket S3 pour le state distant (et locking) et le fournisseur OIDC GitHub Actions.

> [!NOTE]
> Le locking du state est géré via S3 `use_lockfile = true`, sans DynamoDB.

```bash
cd terraform/bootstrap
terraform init
terraform apply -var-file=./env/bootstrap.tfvars
```

### 2. Infrastructure

Déploiement de l'infrastructure coeur via les workspaces Terraform (`dev` ou `prod`).

```bash
cd ../infra
terraform init
terraform workspace select dev || terraform workspace new dev
terraform apply -var-file=./env/dev.tfvars
```

### 3. Application WordPress

Une fois l'infrastructure déployée :

```bash
aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_name) --region eu-west-3

helm upgrade --install wordpress ../../helm/wordpress \
  --set db.host="$(terraform output -raw rds_address)" \
  --set db.name="$(terraform output -raw rds_name)" \
  --namespace "$(terraform output -raw k8s_namespace)" \
  --wait
```

### 4. Destruction

Pour détruire l'infrastructure :

```bash
helm uninstall wordpress -n polycea-wordpress
terraform destroy -var-file=./env/dev.tfvars
```

> [!TIP]
> Le NLB n'est pas managé par Terraform, il est donc nécessaire de désinstaller WordPress avant de détruire l'infrastructure