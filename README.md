> [!IMPORTANT]
> La documentation est en cours de rédaction et peut être amenée à changer

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

> [!NOTE]
> Par souci de simplicité, la StorageClass, le namespace et les secrets k8s sont gérés dans la stack `infra`. Toutefois ce couplage peut créer des problèmes de dépendance, notamment des blocages lors du destroy.

# Stack technique

- **Cloud Provider :** AWS
- **IaC :** Terraform
- **BDD :** AWS RDS (MySQL)
- **CI/CD :** GitHub Actions

# Architecture

<img width="1720" height="1500" alt="aws_simplified_architecture" src="https://github.com/user-attachments/assets/1ba02b7b-426c-4e4f-9dde-8f1bc4abdb97" />

Ci-dessous une description de l'architecture globale du projet. Beaucoup de valeurs (e.g. nombre de sous-réseaux, ...) sont des valeurs par défaut de Terraform et peuvent être configurées à travers un fichier `.tfvars`. Elles seront explicitées plus loin dans la documentation.

## Réseau

Le réseau repose sur 1 VPC réparti sur 2 zones de disponibilité (AZ) sur la région `eu-west-3` :

- **2 sous-réseaux publics** : disposent d'une route vers l'Internet Gateway. Ils accueillent les NAT Gateways + Elastic IP. Kubernetes y déploie automatiquement les Load Balancers.
- **2 sous-réseaux privés** : hébergent les worker nodes ainsi que la base RDS et les points de montage NFS (EFS). Les sous-réseaux privés disposent d'une route vers une NAT Gateway pour les flux sortants.

> [!NOTE]
> Dans un environment `prod-ready` on aurait privilégié une architecture 3-tiers comme le recommande la documentation AWS. Avec deux sous-réseaux `isolated` sans route vers Internet pour les BDD RDS et les points de montage EFS.

## EKS

Le cluster Kubernetes est managé par AWS EKS, on délègue à AWS la responsabilité des mises à jour, backups `etcd`, patch de sécurité et la haute disponibilité (EKS est multi-az).
Les worker nodes sont déployés sur les sous-réseaux privés (distribué entre eux).

EKS déploie automatiquement les Load Balancers pour les services K8S (si `type: LoadBalancer`), par défaut il s'agit de CLB (Classic Load Balancer) et EKS identifie les sous-réseaux valides à travers un tag.

> [!NOTE]
> Aucun mécanisme d'autoscaling (e.g. Karpenter) n'étant installé sur le cluster, les valeurs `min` et `max` ne déclenchent aucun redimensionnement automatique.

### Addons EKS

- **VPC CNI** (addon par défaut géré par AWS) : Attribue aux pods des adresses IP issues des sous-réseaux privés du VPC.
- **EFS CSI Driver** : Permet au cluster de communiquer avec EFS et de monter dynamiquement les volumes NFS partagés dans les pods.
- **EKS Pod Identity Agent** : Permet de délivrer des identifiants IAM aux pods pour leur permettre l'accès à des ressources AWS (e.g. CSI Driver)

## Stockage

- **AWS RDS (MySQL)** : Déployé dans les sous-réseaux privés
- **AWS EFS** : Système de fichiers partagé distribué sur les deux AZ. Il permet le partage des fichiers WordPress (`wp-content`) entre les multiples réplicas de pods (`ReadWriteMany` / `RWX`).

> [!WARNING]
> RDS (port 3306) et EFS (port 2049) acceptent les connexions entrantes depuis un Security Group qui est partagé à la fois par les worker nodes **et** le control plane EKS.

# Helm

L'application WordPress est packagée sous forme d'un chart Helm personnalisé :

- **Image** : Utilisation de l'image `bitnami/wordpress` épinglée par digest SHA256.
- **Contexte de sécurité** :
  - Exécution en non-root (`runAsNonRoot: true`, UID `1001`).
  - Blocage de l'élévation de privilèges (`allowPrivilegeEscalation: false`).
  - Suppression de toutes les capacités Linux (`drop: - ALL`).
  - Profil Seccomp du runtime (`RuntimeDefault`).
- **Probes** :
  - **Readiness Probe** : Requête HTTP sur `/wp-login.php` pour s'assurer que le pod est prêt à recevoir du trafic.
  - **Liveness Probe** : Requête HTTP sur `/license.txt` (fichier statique léger) pour tester l'état du pod.
- **Ressources** : Définition de `requests` (100m CPU / 256Mi RAM) et `limits` (500m CPU / 512Mi RAM).
- **Persistance** : Le volume monté sur `/bitnami/wordpress/` est adossé à un PVC réclamant la `StorageClass` EFS (`efs-sc`) en mode `ReadWriteMany`, assurant le partage des fichiers (wp-content, plugins, thèmes) entre les réplicas.

> [!NOTE]
> L'image `bitnami/wordpress` a été préférée à l'image officielle car elle tourne nativement en non-root et tolère la suppression complète des capacités Linux.

> [!WARNING]
> Le chart Helm n'est pas `prod-ready` sur plusieurs aspects :
> - **Absence de `podAntiAffinity`** : Rien n'empêche le scheduler de planifier tous les réplicas sur le même worker node, créant un SPOF.
> - **Gestion des secrets** : Les identifiants MySQL sont générés et stockés dans un `Secret` Kubernetes (base64 dans etcd) via le provider Terraform. En environnement `prod-ready`, on utiliserait un Secrets Manager.

# CI/CD

L'authentification auprès d'AWS s'effectue via une fédération d'identité OIDC (OpenID Connect) entre GitHub et AWS IAM. 
Deux rôles AWS sont utilisés pour ce pipeline :

- `github-oidc-role-terraform-polycea-wp` : Provisionné par la stack `bootstrap`. Il accorde à Terraform la policy `AdministratorAccess` sur le compte AWS.
- `github-oidc-role-helm-polycea-wp-${env}` : Provisionné par la stack `infra`. Il accorde au workflow Helm l'action AWS `eks:DescribeCluster` et associe l'access entry EKS `AmazonEKSEditPolicy` restreinte au namespace `polycea-wordpress`.

La chaîne se compose de 4 pipelines :

- `terraform-lint.yml` : Linting et vérification de formatage à chaque PR ou push.
- `terraform-apply.yml` : Déploiement de l'infrastructure via `workflow_dispatch` avec sélection manuelle de l'environnement.
- `helm-lint.yml` : Validation syntaxique du chart (`helm lint`) à chaque PR ou push.
- `helm-install.yml` : Déploiement de la release Helm sur le cluster EKS cible.

> [!WARNING]
> Ce pipeline n'est pas `prod-ready` sur plusieurs points :
> - **Permissions IAM trop permissives** : Le rôle OIDC GitHub Actions utilise la politique `AdministratorAccess`. En production, les permissions devraient être restreintes selon le principe du moindre privilège aux seules ressources du projet.
> - **Absence de scan de sécurité**
> - **Gestion des environnements** : Le déclenchement manuel via `workflow_dispatch` sur un dépôt unique présente des risques d'erreur humaine. Une approche GitOps (e.g. ArgoCD) avec des branches ou des dépôts distincts serait préférable.

# Environnements

Le projet fonctionne autour de deux environnements : `dev` et `prod`. L'objectif est de réduire les coûts et le temps de déploiement en développement.

- **NAT Gateway** : 1 seule NAT Gateway en `dev` pour tous les sous-réseaux privés (contre 1 par AZ en `prod` pour la haute disponibilité).
- **RDS** : Déployé en Single-AZ en `dev` et `skip_final_snapshot: true` (réduit le temps nécessaire à la destruction)

Actuellement, la séparation repose sur :

- **AWS** : Un compte unique, différenciation par tags.
- **Terraform** : Deux workspaces pour séparer les `.tfstate`, avec des fichiers `.tfvars` distincts.
- **CI/CD** : Un choix d'environnement au lancement du workflow.

> [!WARNING]
> Cette séparation n'est pas `prod-ready` :
> - **Compte unique** : Pas de frontière de sécurité étanche entre `dev` et `prod`. En `prod-ready`, on utiliserait des comptes AWS dédiés via AWS Organizations.
> - **Workspaces Terraform** : Déconseillés par HashiCorp pour isoler des environnements. On préférerait des répertoires/modules dédiés avec des backends S3 distincts.
> - **CI/CD** : On aurait pu avoir deux repos distincts.
