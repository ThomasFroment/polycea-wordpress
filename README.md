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
> Dans un environment `prod-ready` on aurait privilégier une architecture 3-tiers comme le recommande la documentation AWS. Avec deux sous-réseaux `isolated` sans route vers Internet pour les BDD RDS et les points de montage EFS.

## EKS

Le cluster Kubernetes est managé par AWS EKS, on délègue à AWS la responsabilité des mises à jour, backups `etcd`, patch de sécurité et la haute disponibilité (EKS est multi-az).
Les worker nodes sont déployé sur les sous-réseaux privés (distribué entre eux).

EKS déploie automatiquement les Loads Balancer pour les services K8S (si `type: LoadBalancer`), par défaut il s'agit de CLB (Classic Load Balancer) et EKS identifie les sous-réseaux valides à travers un tag.

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

# Environments

Le projet fonctionne autour de deux environnements : `dev` et `prod`. L'objectif est de réduire les coûts et le temps de déploiement en développement.

- **NAT Gateway** : 1 seule NAT Gateway en `dev` pour tous les sous-réseaux privés (contre 1 par AZ en `prod` pour la haute disponibilité).
- **RDS** : Déployé en Single-AZ en `dev` et `skip_final_snapshot: true` (réduit le temp nécessaire à la destruction)

Actuellement, la séparation repose sur :

- **AWS** : Un compte unique, différenciation par tags.
- **Terraform** : Deux workspaces pour séparer les `.tfstate`, avec des fichiers `.tfvars` distincts.
- **CI/CD** : Un choix d'environnement au lancement du workflow.

> [!WARNING]
> Cette séparation n'est pas `prod-ready` :
> - **Compte unique** : Pas de frontière de sécurité étanche entre `dev` et `prod`. En `prod-ready`, on utiliserait des comptes AWS dédiés via AWS Organizations.
> - **Workspaces Terraform** : Déconseillés par HashiCorp pour isoler des environnements. On préférerait des répertoires/modules dédiés avec des backends S3 distincts.
> - **CI/CD** : On aurait pu avoir deux repos distincts.


