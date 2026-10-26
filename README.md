# argocd-app-of-apps-demo

A two-tier Python app (frontend + backend) deployed with **Argo CD** using the
**app-of-apps** pattern, across **two Kubernetes clusters**, exposed through **Traefik**.

Built as a hands-on learning project to understand GitOps beyond a single `Application`:
how apps create apps, how AppProjects act as guardrails, and how a central Argo CD
deploys to a separate workload cluster.

## What this demonstrates

- **App-of-apps**: one root Application discovers and creates a child Application for
  every file in `apps/` — adding a service means adding two files, no edits to the root.
- **Hub-and-spoke deployment**: Argo CD runs on one cluster; the workloads run on another.
- **AppProjects as least-privilege guardrails**: the root may only create Applications;
  the workload apps may only deploy a fixed set of kinds into one namespace on one cluster.
- **Ingress routing with Traefik**: one host, path-based routing to two services.
- **Clean deletion**: finalizers so removing an app from Git removes its resources too.
- **Multi-arch images**: built with `docker buildx` for `amd64` and `arm64`.

## Architecture

```
ARGO CD CLUSTER (kubernetes.default.svc)                 DEV CLUSTER (dev-control-plane)
  namespace: argocd                                        namespace: product1-ns

  product1-root  ── reads apps/ in this repo ──┐
  (project: product1-bootstrap)                │
                                               ├─► product1-frontend ──► Deployment, Service, Ingress
                                               └─► product1-backend  ──► Deployment, Service, Ingress
                                                   (project: product1-project)

                                     browser ──► Traefik :30101 ──┬─ /     ──► frontend-svc ──► frontend pod :4000
                                                                  └─ /api  ──► backend-svc  ──► backend pod  :5000
                                                 frontend pod ── http://backend-svc/api/message ──► backend (in-cluster)
```

The root app and AppProjects are defined in my platform repo,
[argocd-manifests](https://github.com/rdomala-netizen/argocd-manifests)
(`applications/product1-root.yaml`, `projects/product1.yaml`). This repo holds
everything the root and its children read.

## Repository layout

```
argocd-app-of-apps-demo/
├── src/                      # application source
│   ├── frontend/  app.py  Dockerfile     # Flask, port 4000, calls the backend
│   └── backend/   app.py  Dockerfile     # Flask, port 5000, serves /api/message
├── build-push.sh             # multi-arch build + push to Docker Hub
├── apps/                     # child Applications — the root app watches this folder
│   ├── product1-frontend.yaml
│   └── product1-backend.yaml
└── manifests/                # workloads, one folder per service
    ├── frontend/  deploy.yaml  svc.yaml  ingress.yaml
    └── backend/   deploy.yaml  svc.yaml  ingress.yaml
```

| | Frontend | Backend |
|---|---|---|
| Image | [`rdomala/product1-frontend`](https://hub.docker.com/r/rdomala/product1-frontend) | [`rdomala/product1-backend`](https://hub.docker.com/r/rdomala/product1-backend) |
| Container port | 4000 | 5000 |
| Service | `frontend-svc:80` | `backend-svc:80` |
| Ingress path | `/` | `/api` |
| Argo CD app | `product1-frontend` | `product1-backend` |

## Design decisions

**App-of-apps over ApplicationSet.** ApplicationSet templates many similar apps from
one definition, which is the better tool at scale. App-of-apps keeps every Application
as a plain, readable file, which made each moving part visible while learning.

**Two AppProjects instead of one.** The root and the workloads need opposite
permissions: the root writes `Application` objects into `argocd`; the workloads must
never touch `argocd`. A single project would have to allow both.

| Project | Used by | May deploy | Into |
|---|---|---|---|
| `product1-bootstrap` | `product1-root` | Argo CD `Application` objects only | `argocd` on the Argo CD cluster |
| `product1-project` | frontend, backend | Namespace, Deployment, Service, ConfigMap, Secret, Ingress | `product1-ns` on the dev cluster |

**Root on the Argo CD cluster, workloads on the dev cluster.** Application objects only
mean something to Argo CD, so they live next to it. Only the workloads are sent to the
target cluster.

**Pinned image tags.** Releases happen by bumping the tag in Git, so every deployed
version is traceable to a commit.

**Backend reachable two ways.** Externally through the Ingress at `/api`, and from the
frontend in-cluster via `backend-svc` — so the frontend doesn't depend on the Ingress.

## Running it

Prerequisites: Argo CD on one cluster with `dev-control-plane` registered; Traefik on the
dev cluster on NodePort 30101, published to the host via kind `extraPortMappings`.

```bash
# 1. Images (already published — only needed after code changes)
./build-push.sh v1.0.0

# 2. On the Argo CD cluster, from the argocd-manifests repo
kubectl apply -f projects/product1.yaml            # guardrails first
kubectl apply -f applications/product1-root.yaml   # then the root — Argo CD does the rest

# 3. Try it
curl http://product1.localhost:30101/              # frontend, includes the backend's reply
curl http://product1.localhost:30101/api/message   # backend directly
```

Expected response from `/`:

```json
{
  "service": "frontend",
  "ui_message": "Hello from Frontend",
  "backend_response": {
    "service": "backend",
    "message": "Hello from Backend API",
    "status": "success"
  }
}
```

## Day-2 operations

| Task | How |
|---|---|
| Release a new version | `./build-push.sh v1.0.1`, bump the tag in `manifests/<service>/deploy.yaml`, push |
| Add a service | Add `manifests/<service>/` and `apps/product1-<service>.yaml`, push — the root picks it up |
| Remove a service | Delete its file from `apps/`, push — the root prunes it and the finalizer removes its resources |

## Experiments

- Scale the backend to zero and curl `/` — the frontend reports `backend unreachable`,
  then self-heal restores the replica because Git still says `replicas: 1`.
- Edit a Service with `kubectl edit` and watch Argo CD revert it.
- Add a `ClusterRole` to `manifests/backend/` — the sync fails with
  *not permitted in project*, which is the AppProject doing its job.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `connection refused` on :30101 | kind `extraPortMappings` missing for 30101 on the dev cluster |
| `404 page not found` from Traefik | Ingress not picked up — check `ingressClassName` and `kubectl get ingress -n product1-ns` |
| `ImagePullBackOff` | Tag not pushed to Docker Hub |
| `backend unreachable` in the frontend response | Backend pod down, or the Service selector doesn't match the pod label |
| `application destination ... is not permitted in project` | App's `destination` doesn't exactly match the project's `destinations` |
| No pods in `product1-ns` | You're on the Argo CD cluster's kube context — the pods run on the dev cluster |

## Credits

The original frontend/backend apps and the multi-repo layout come from
[CloudWithVarJosh](https://github.com/CloudWithVarJosh)'s product1 demo. I restructured
it into a single GitOps repo and added the AppProjects, Traefik Ingress, finalizers,
multi-cluster deployment and multi-arch builds.
