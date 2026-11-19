#!/usr/bin/env bash
set -euo pipefail
# Export sensitive live release metadata OUTSIDE the GitOps Git repository.
# This is a configuration export, not a database / repository backup.
OUT="$HOME/gitlab-migration-private/$(date +%Y%m%d-%H%M%S)"
umask 077
mkdir -p "$OUT"
helm get values gitlab -n gitlab -o yaml > "$OUT/old-user-values.yaml"
helm get manifest gitlab -n gitlab > "$OUT/old-rendered-manifest.yaml"
helm history gitlab -n gitlab > "$OUT/helm-history.txt"
kubectl get pvc -n gitlab -o yaml > "$OUT/pvc.yaml"
kubectl get pv -o yaml > "$OUT/pv.yaml"
kubectl get ingress -n gitlab -o yaml > "$OUT/ingress.yaml"
kubectl get deployments,statefulsets -n gitlab -o yaml > "$OUT/workloads.yaml"
echo "Exported to $OUT"
echo 'WARNING: these files may contain sensitive data. Do not commit or upload them to GitHub.'
echo 'WARNING: this is NOT a full PostgreSQL/Gitaly/MinIO/Registry backup.'
