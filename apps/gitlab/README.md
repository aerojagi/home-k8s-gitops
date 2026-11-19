# GitLab via Argo CD (staged, NOT yet installed)

- Argo CD Application: `clusters/home-lab/20-gitlab-application.yaml`
- Chart: official `gitlab` chart from `https://charts.gitlab.io`
- Pinned chart version: `9.10.8` (same as the last successful Helm revision)
- Values: `apps/gitlab/values.yaml` in **this GitHub repository**.
- Ingress: `global.ingress.provider=traefik`, `global.ingress.class=traefik`.
- Existing controller: RKE2 `rke2-traefik`; both bundled ingress controllers disabled.

## Blockers before sync

1. `k8s-worker-1` must have functional ClusterIP routing, kube-proxy and Canal (`2/2`).
2. MinIO, PostgreSQL and Gitaly volumes must be protected with backups. `local-path` storage is node-local.
3. Existing Helm values, hostnames, TLS secret names, credentials references and persistence settings must be migrated into Git. The example Traefik-only file is NOT a full migration.
4. Do not commit passwords, tokens, unencrypted exported secrets, kubeconfigs or TLS private keys.
5. Plan existing release handoff. Argo CD uses Helm to **render**, not to manage the old Helm release lifecycle.
6. Confirm GitLab chart's generated hooks, CRDs, `IngressRouteTCP`, PV/PVC ownership, and secret generation before the first manual sync.
7. Configure Traefik's matching GitLab Shell TCP entrypoint for SSH (port 2222 suggested for this lab) before testing SSH.

## Inspect, do not sync yet

```bash
kubectl -n argocd get applications home-lab-root hello-gitops gitlab
kubectl -n gitlab get pvc,pods,ingress
kubectl -n kube-system get ds rke2-canal rke2-traefik
```

With chart 9.10.8, bundled PostgreSQL/Redis/MinIO are slated for removal from later major GitLab charts. Plan external services before upgrading chart major versions.
