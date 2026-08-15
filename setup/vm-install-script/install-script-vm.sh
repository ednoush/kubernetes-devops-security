#!/bin/bash
#
# Script adapté pour Ubuntu 22.04 (Jammy Jellyfish)
# Basé sur le script original, mis à jour car :
#   - l'ancien dépôt apt.kubernetes.io (kubernetes-xenial) est fermé depuis 2023
#   - apt-key est déprécié sur 22.04 -> remplacé par des keyrings signed-by
#   - dockershim a été retiré de kubelet depuis Kubernetes 1.24 -> containerd requis
#   - Weave Net n'est plus maintenu (Weaveworks a cessé son activité en 2024) -> remplacé par Calico
#   - Jenkins a changé ses clés de signature de dépôt en décembre 2025
#
# Choix retenus (d'après tes réponses) :
#   - Kubernetes version récente et supportée (1.34, cf. https://kubernetes.io/releases/)
#   - Runtime : containerd (utilisé par kubelet/CRI) + Docker Engine installé en plus
#     (pratique pour "docker build"/"docker ps", mais ce n'est PAS le CRI utilisé par kubelet)
#   - CNI : Calico (manifeste simple, non-operator) à la place de Weave

set -euo pipefail

echo ".........----------------#################._.-.-INSTALL-.-._.#################----------------........."

# --- Prompt coloré (inchangé, fonctionne toujours sur 22.04) ---
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
echo "PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '" >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
# NB: "source ~/.bashrc" n'a de sens qu'en shell interactif ; on l'omet ici pour un script exécuté avec bash script.sh

export DEBIAN_FRONTEND=noninteractive

# Certaines VM/réseaux n'ont pas de connectivité IPv6 fonctionnelle : apt essaie IPv6 en premier
# et échoue avec "Network is unreachable" même si IPv4 fonctionne. On force IPv4 par sécurité.
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

apt-get autoremove -y
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
systemctl daemon-reload

echo ".........----------------#################._.-.-PRE-REQUIS KUBEADM-.-._.#################----------------........."

# --- Désactivation du swap (obligatoire pour kubeadm) ---
swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

# --- Modules noyau et sysctl requis par Kubernetes ---
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo ".........----------------#################._.-.-CONTAINERD + DOCKER-.-._.#################----------------........."

# containerd sera le runtime utilisé par kubelet (CRI).
# docker.io est installé en plus pour pouvoir utiliser la commande "docker" (build, ps, etc.)
apt-get install -y docker.io containerd vim build-essential jq python3-pip
pip3 install jc

### UUID de la VM
### commente la ligne ci-dessous si ce script n'est pas exécuté sur une VM cloud
jc dmidecode | jq .[1].values.uuid -r || true

# Config Docker (inchangée)
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d

# Config containerd : driver cgroup systemd obligatoire avec kubelet moderne
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd
systemctl restart docker
systemctl enable docker

echo ".........----------------#################._.-.-KUBERNETES-.-._.#################----------------........."

# Nouveau dépôt officiel (remplace apt.kubernetes.io / kubernetes-xenial, fermés depuis 2023)
KUBE_VERSION=1.34          # branche mineure (parmi les versions supportées : 1.34 / 1.35 / 1.36)
KUBE_FULL_VERSION=1.34.9   # dernier patch connu au moment de la rédaction, à ajuster si besoin

mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key" | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet="${KUBE_FULL_VERSION}-*" kubeadm="${KUBE_FULL_VERSION}-*" kubectl="${KUBE_FULL_VERSION}-*"
apt-mark hold kubelet kubeadm kubectl

# kubelet utilise containerd comme CRI
mkdir -p /var/lib/kubelet
cat <<EOF > /etc/default/kubelet
KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock
EOF

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

echo ".........----------------#################._.-.-INIT DU CLUSTER-.-._.#################----------------........."
rm -f /root/.kube/config
kubeadm reset -f

# décommente la ligne suivante si l'hôte n'a pas le minimum requis de 2 CPU
# kubeadm init --kubernetes-version=v${KUBE_FULL_VERSION} --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=NumCPU --skip-token-print
kubeadm init --kubernetes-version="v${KUBE_FULL_VERSION}" --pod-network-cidr=192.168.0.0/16 --skip-token-print

mkdir -p ~/.kube
cp -i /etc/kubernetes/admin.conf ~/.kube/config

# Calico remplace Weave (non maintenu depuis l'arrêt de Weaveworks en 2024)
# Manifeste "single file" (installation simple, non basée sur l'opérateur Tigera)
CALICO_VERSION=v3.32.1
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

sleep 60

echo "untaint controlplane node"
NODE_NAME=$(kubectl get nodes -o=jsonpath='{.items[0].metadata.name}')
# "master" est l'ancien label (<1.24), "control-plane" est le nouveau : on retire les deux au cas où
kubectl taint node "${NODE_NAME}" node.kubernetes.io/not-ready:NoSchedule- 2>/dev/null || true
kubectl taint node "${NODE_NAME}" node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
kubectl taint node "${NODE_NAME}" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
kubectl get node -o wide

echo ".........----------------#################._.-.-JAVA ET MAVEN-.-._.#################----------------........."
# Jenkins récent nécessite Java 17 minimum (Java 21 recommandé) -> on installe le JDK complet
# (nécessaire pour que "mvn" compile aussi, pas seulement pour faire tourner Jenkins)
apt-get install -y openjdk-21-jdk
java -version
apt-get install -y maven
mvn -v

echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."
# Nouvelles clés de signature du dépôt Jenkins depuis décembre 2025 (jenkins.io-2026.key)
# apt-key est déprécié sur 22.04 -> on utilise un keyring signed-by
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | \
  tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update

# Version LTS Jenkins actuelle au moment de la rédaction (05/08/2026) : https://www.jenkins.io/changelog-stable/
JENKINS_VERSION=2.568.2
apt-get install -y jenkins="${JENKINS_VERSION}"
apt-mark hold jenkins
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins
#systemctl status jenkins
usermod -a -G docker jenkins

# ATTENTION : donne à jenkins un accès root complet sans mot de passe. Pratique en lab,
# à proscrire en production (préférer des règles sudoers limitées aux commandes nécessaires).
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."