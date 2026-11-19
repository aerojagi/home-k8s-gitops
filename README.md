# Home RKE2 GitOps lab — GitHub + Argo CD + GitLab + Traefik

This project is a starter GitOps repository prepared for an existing five-node **RKE2** lab. It deliberately **does not uninstall GitLab** or automatically sync GitLab. The most recent GitLab chart deployed by Helm was **9.10.8, revision 4**. The GitLab ingress override was prepared to use the **existing RKE2 Traefik controller**.

## Architecture

```
GitHub repo (configuration, version pins)
       |
       v
Argo CD home-lab-root (bootstrap app-of-apps)
       +--> hello-gitops: ConfigMap demo (auto-sync)
       +--> gitlab: official GitLab Helm chart 9.10.8 + GitHub-hosted values (MANUAL SYNC)
                  |
                  v
        RKE2 workload pods / PVCs / existing Traefik controller
```

Argo CD uses Helm to **render templates**; it does not create a normal `helm install` release. The GitLab Application combines the public chart from `https://charts.gitlab.io` and `$values/apps/gitlab/values.yaml` from your GitHub repository.

## Repository layout

```
bootstrap/root-application.yaml             # initial one-time kubectl apply
clusters/home-lab/00-project.yaml           # Argo CD AppProject
clusters/home-lab/10-hello-application.yaml # safe first GitOps demo
clusters/home-lab/20-gitlab-application.yaml # GitLab staged, manual sync
apps/hello-gitops/configmap.yaml            # edit to test Git -> cluster
apps/gitlab/values.yaml                     # IMPORTANT: needs complete values before sync
apps/gitlab/README.md                       # GitLab safety checklist
tools/preflight.sh                           # check lab readiness
tools/export-existing-helm.sh               # preserve old config outside Git
```

## Phase 0 — Recovery and preservation (MANDATORY before GitLab cutover)

At the time of this starter project, `k8s-worker-1` could reach the API directly, but NOT the Service IP `10.43.0.1:443`. kube-proxy was exiting; Canal was `Init:Error`; MinIO and PostgreSQL were unavailable on that worker. A Helm-to-Argo switch will **not** cure broken node networking.

1. Restore `k8s-worker-1` **kube-proxy**, Service routing, and Canal. Verify `curl -ksS --noproxy '*' https://10.43.0.1:443/version` on that worker responds (unauthenticated HTTP 401 is fine).
2. Run `bash tools/preflight.sh`. All five Canal pods must be ready.
3. Preserve the present Helm configuration **locally**, outside the repository: `bash tools/export-existing-helm.sh`.
4. Make verified backups of actual GitLab data (PostgreSQL, Gitaly repositories, MinIO buckets/Registry, Redis where applicable) and the GitLab Kubernetes Secrets. For local-path volumes on worker1, protect the VM disk / PV storage. Configuration exports are not a replacement for these backups.
5. Record and verify PV reclaim policy, node affinity and existing PVC names BEFORE uninstalling. With `local-path`, deleting a PVC may lead to permanent loss of underlying files.

Do **not** run `kubectl delete namespace gitlab`, delete PVCs/PVs, or use `helm uninstall` until the above is completed and the old release handoff is deliberately planned.

## Phase 1 — Create the GitHub repository

Create a **private**, empty repository at https://github.com/new named `home-k8s-gitops` under `aerojagi`. Avoid initializing it with a README, because this folder already contains one.

Unzip the project and from inside the `home-k8s-gitops` folder:

```bash
git init -b main
git add .
git commit -m 'feat(gitops): bootstrap home lab and stage GitLab chart'
git remote add origin git@github.com:aerojagi/home-k8s-gitops.git
git push -u origin main
```

If you lack GitHub SSH access locally, use GitHub's HTTPS remote for the **push** (`https://github.com/aerojagi/home-k8s-gitops.git`) after configuring Git Credential Manager or `gh auth login`. Keep all Secrets outside this repository.

## Phase 2 — Connect Argo CD to private GitHub

Argo CD must already be installed and healthy (`kubectl get ns argocd`). Configure a **read-only GitHub deploy key** for the repository: create a dedicated SSH keypair, put the public key in GitHub repository **Settings > Deploy keys** (read-only), then add the corresponding private key in **Argo CD > Settings > Repositories > Connect Repo > SSH**. Use the repository URL:

```
git@github.com:aerojagi/home-k8s-gitops.git
```

Do not put an SSH private key in Git or in a ConfigMap. Argo CD also needs outbound network access to GitHub and `https://charts.gitlab.io`.

## Phase 3 — Bootstrap your first GitOps project

From the RKE2 cluster (with the private GitHub repo accessible to Argo CD):

```bash
kubectl get crd applications.argoproj.io appprojects.argoproj.io
kubectl apply -f bootstrap/root-application.yaml
kubectl -n argocd get applications -w
```

`home-lab-root` automatically creates the AppProject, a harmless `hello-gitops` demo app, and the staged GitLab app. The **GitLab app has no automated sync**.

Verify your first success:

```bash
kubectl -n gitops-demo get configmap hello-from-github -o yaml
```

Now edit `apps/hello-gitops/configmap.yaml` (change the `message`), commit and push. Argo CD should reconcile the ConfigMap and demonstrate the GitHub -> Argo CD -> Kubernetes flow.

## Phase 4 — Prepare GitLab values in GitHub

The supplied `apps/gitlab/values.yaml` is intentionally ONLY the Traefik override. Before the first GitLab sync, reconcile it with the **old release's full user-supplied values**:

```bash
helm get values gitlab -n gitlab -o yaml
```

Pay attention to `global.hosts`, global ingress/TLS secret names, external URL, minio, Gitaly, PostgreSQL, Registry, KAS, Redis, persistence, SMTP, certificate management and existing Secret names. Convert sensitive literal values to references to previously created Kubernetes Secrets, or set up SOPS/External Secrets before committing. **Do not commit raw values exports containing credentials**.

Keep the Traefik overrides:

```yaml
global:
  ingress:
    enabled: true
    class: traefik
    provider: traefik
nginx-ingress:
  enabled: false
traefik:
  enabled: false
```

The GitLab Shell `IngressRouteTCP` needs a matching TCP entrypoint in RKE2 Traefik, and client SSH port 2222 is suggested because the Ubuntu hosts use SSH port 22. KAS/Registry/TLS must be tested separately after HTTP routing is healthy.

## Phase 5 — Cutover (NOT AUTOMATED)

**Two different strategies exist:**

- **Preserve GitLab and its data (recommended):** first restore cluster health and backups. Review the Argo CD rendered diff against the existing Helm-managed resources; plan ownership handoff and persistent storage/secret preservation. Do not uninstall the old Helm release while the same live resources are being actively managed by Argo CD: `helm uninstall` can still delete them.
- **Deliberately start a new, empty GitLab:** only if losing existing projects, databases, image layers and configuration is acceptable, or after verified backups and a restore plan. Review PV reclaim policy and Secrets; after safe preservation, the old release can be removed with `helm uninstall gitlab -n gitlab`. This command is destructive to live workloads and may destroy data if related PVCs are deleted. Do not delete the namespace or PVs blindly.

When the desired GitLab chart render, Secrets and PVC plan are validated, use **manual** sync of the Argo CD `gitlab` Application. Verify GitLab UI, authentication, DB migrations, Gitaly, Registry pull/push, MinIO, KAS, SSH and Traefik routes before enabling auto-sync. Keep GitLab pruning DISABLED initially.

## Optional next milestones

- Add Traefik's own HelmChartConfig and HTTPS certificate management to Git (avoid having Argo CD fight RKE2's packaged-chart manifests).
- Add SOPS/age or External Secrets for encrypted/referenced credentials.
- Add GitHub branch protection and Pull Request reviews for changes to GitLab values.
- Extend with separate namespaces and apps for monitoring, OpenBao and later workload clusters.

## Sources

- Argo CD multiple sources: https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/
- Argo CD Helm: https://argo-cd.readthedocs.io/en/stable/user-guide/helm/
- GitLab chart Traefik: https://docs.gitlab.com/charts/charts/traefik/
- GitLab chart external ingress: https://docs.gitlab.com/charts/advanced/external-ingress/
