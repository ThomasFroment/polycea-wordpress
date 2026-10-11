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
- **2 sous-réseaux publics** : disposent d'une route vers l'Internet Gateway. Ils accueillent les NAT Gateways + Elastic IP. Kubernetes y déploie automatiquement les Load Balancers (CLB par défaut).
- **2 sous-réseaux privés** : hébergent les worker nodes ainsi que la base RDS et les points de montage NFS (EFS). Les sous-réseaux privés disposent d'une route vers une NAT Gateway pour les flux sortants.

> [!NOTE]
> Pour des raisons de coût, dans l'environnement `dev`, l'infrastructure ne provisionne qu'une seule NAT Gateway pour tous les sous-réseaux privés.

## EKS

Le cluster Kubernetes est managé par AWS EKS, les worker nodes sont déployés dans les sous-réseaux privés.

> [!NOTE]
> Aucun mécanisme d'autoscaling (e.g. Karpenter) n'étant installé sur le cluster, les valeurs `min` et `max` ne déclenchent aucun redimensionnement automatique.

### Addons EKS

- **VPC CNI** (addon par défaut géré par AWS) : Attribue aux pods des adresses IP issues des sous-réseaux privés du VPC.
- **EFS CSI Driver** : Permet au cluster de communiquer avec EFS et de monter dynamiquement les volumes NFS partagés dans les pods.
- **EKS Pod Identity Agent** : Permet de délivrer des identifiants IAM aux pods pour leur permettre l'accès à des ressources AWS (e.g. CSI Driver)

## Stockage

- **AWS RDS (MySQL)** : Déployé dans les sous-réseaux privés
- **AWS EFS** : Système de fichiers partagé distribué sur les deux AZ. Il permet le partage des fichiers WordPress (`wp-content`) entre les multiples réplicas de pods (`ReadWriteMany`).

Les security group d'EFS (port 2049) et de RDS (port 3306) n'acceptent de connexions que depuis le Security Group du cluster EKS.

> [!NOTE]
> Pour des raisons de coût, dans l'environnement `dev`, la BDD RDS n'utilise pas le mode `multi-az` (qui fournit de la haute disponibilité en `prod`).

> [!WARNING]
> RDS et EFS acceptent les connexions entrantes depuis un security group qui est partagé à la fois par les worker nodes **et** le control plane EKS.


