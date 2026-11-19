#!/usr/bin/env bash
set -euo pipefail

echo '--- Nodes ---'
kubectl get nodes -o wide

echo '--- Canal rollout ---'
kubectl -n kube-system get ds rke2-canal -o wide
READY=$(kubectl -n kube-system get ds rke2-canal -o jsonpath='{.status.numberReady}')
DESIRED=$(kubectl -n kube-system get ds rke2-canal -o jsonpath='{.status.desiredNumberScheduled}')
if [[ "$READY" != "$DESIRED" ]]; then
  echo "BLOCKED: Canal is only $READY/$DESIRED ready. Do not uninstall/sync GitLab."
  exit 2
fi

echo '--- GitLab pods, PVCs and services ---'
kubectl -n gitlab get pods -o wide || true
kubectl -n gitlab get pvc || true
kubectl -n gitlab get ingress || true

echo '--- MinIO endpoints ---'
kubectl -n gitlab get endpointslices -l kubernetes.io/service-name=gitlab-minio-svc || true

echo 'Canal is ready. IMPORTANT: this is not proof that GitLab backups or persistence are safe.'
