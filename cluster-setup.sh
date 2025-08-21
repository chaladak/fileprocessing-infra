#!/bin/bash
set -e

echo "=== Setting up ArgoCD ==="
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.1.0/manifests/install.yaml

wget -q https://github.com/argoproj/argo-cd/releases/download/v3.1.0/argocd-linux-amd64
mv argocd-linux-amd64 argocd
chmod +x argocd
sudo mv argocd /usr/local/bin/

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

echo "Initial ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 -d
echo
echo "Run: argocd login <ARGOCD_SERVER_NODEIP:PORT>"

argocd repo add https://github.com/chaladak/fileprocessing-infra.git || true


echo "=== Setting up Argo Workflows ==="
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.1/install.yaml
kubectl patch svc argo-server -n argo -p '{"spec": {"type": "NodePort"}}'

curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.0/argo-linux-amd64.gz
gunzip -f argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv argo-linux-amd64 /usr/local/bin/argo

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflowtaskresults-role
  namespace: argo
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflowtaskresults"]
  verbs: ["create","get","list","watch","update","patch","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflowtaskresults-binding
  namespace: argo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argo-workflowtaskresults-role
subjects:
- kind: ServiceAccount
  name: argo
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflow-role
  namespace: argo
rules:
- apiGroups: [""]
  resources: ["pods","pods/log"]
  verbs: ["create","get","list","watch","update","patch","delete"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows","workflowtemplates","cronworkflows","workflowtaskresults","workflowtasksets"]
  verbs: ["create","get","list","watch","update","patch","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflow-binding
  namespace: argo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argo-workflow-role
subjects:
- kind: ServiceAccount
  name: argo
  namespace: argo
EOF


echo "=== Setting up Argo Events ==="
kubectl create namespace argo-events || true
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/namespace-install.yaml -n argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml -n argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml -n argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/sensor-rbac.yaml -n argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/workflow-rbac.yaml -n argo-events

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-events-sa
  namespace: argo-events
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argo-events-workflow-access
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflowtemplates","workflows"]
  verbs: ["get","list","create","update","patch","delete"]
EOF


echo "=== Deploying fileprocessing-infra via ArgoCD ==="
kubectl apply -f fileprocessing-infra/deploy/argocd/ -n argocd

echo "=== Setup Complete ==="
