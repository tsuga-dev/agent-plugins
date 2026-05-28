# OTel Collector — Kubernetes Deployment Patterns

## Deployment Path Decision Gate

| Environment | Action |
|-------------|--------|
| **Kubernetes** | **Use the Helm chart** — `references/helm-chart.md` is the preferred path. The Tsuga Helm chart deploys the full dual-pattern (agent DaemonSet + cluster receiver) with RBAC, credentials, and sensible defaults. |
| Non-Kubernetes (bare metal, VM, docker-compose) | Use raw YAML below |
| Kubernetes but Helm unavailable or CRDs restricted | Use raw YAML below |

> **Stop here for Kubernetes deployments.** Load `references/helm-chart.md` instead of continuing.

---

## Manual Deployment (Non-Helm)

The sections below apply to non-Kubernetes environments or advanced edge cases where the Helm chart cannot be used.

## Deployment Topology Decision Table

| Pattern | When to Use | Tradeoffs |
|---------|-------------|-----------|
| **DaemonSet** (Agent) | Default for most deployments; one Collector per node | Collects node-level host metrics; proxies app OTLP; lower latency |
| **Deployment** (Gateway) | Central processing: tail sampling, cross-node aggregation, fan-out | More complex; requires loadbalancingexporter for tail sampling |
| **Sidecar** | Per-pod; when app can't set OTLP endpoint; needs strong isolation | Higher resource cost; harder to manage at scale |

## Standard DaemonSet Pattern

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otelcol-agent
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: otelcol-agent
  template:
    metadata:
      labels:
        app: otelcol-agent
    spec:
      serviceAccountName: otelcol
      containers:
        - name: otelcol
          image: otel/opentelemetry-collector-contrib:0.120.0
          args: ["--config=/conf/config.yaml"]
          resources:
            requests:
              memory: 256Mi
              cpu: 100m
            limits:
              memory: 512Mi   # memory_limiter limit_percentage is relative to this
              cpu: 500m
          ports:
            - containerPort: 4317  # OTLP gRPC
            - containerPort: 4318  # OTLP HTTP
            - containerPort: 8888  # Collector metrics
          volumeMounts:
            - name: config
              mountPath: /conf
            - name: storage
              mountPath: /var/lib/otelcol/file_storage
          env:
            - name: K8S_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
      volumes:
        - name: config
          configMap:
            name: otelcol-agent-config
        - name: storage
          emptyDir: {}
```

## Downward API for Pod Metadata

Inject pod metadata into the Collector's own resource attributes (needed for Collector self-telemetry):

```yaml
env:
  - name: K8S_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: K8S_POD_UID
    valueFrom:
      fieldRef:
        fieldPath: metadata.uid
  - name: K8S_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
```

See `otel-instrumentation` → `references/k8s-deployment.md` for the application-side Downward API pod spec.

## RBAC for k8s_attributes

The Collector's ServiceAccount needs cluster-level read access:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otelcol
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otelcol
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes", "endpoints"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["replicasets", "deployments", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: otelcol
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otelcol
subjects:
  - kind: ServiceAccount
    name: otelcol
    namespace: monitoring
```

## Gateway Deployment Pattern (Tail Sampling)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otelcol-gateway
  namespace: monitoring
spec:
  replicas: 3  # Scale based on trace volume
  selector:
    matchLabels:
      app: otelcol-gateway
  template:
    spec:
      containers:
        - name: otelcol
          image: otel/opentelemetry-collector-contrib:0.120.0
          resources:
            requests:
              memory: 1Gi    # Tail sampling buffers full traces in memory
              cpu: 500m
            limits:
              memory: 2Gi
              cpu: 2000m
---
apiVersion: v1
kind: Service
metadata:
  name: otelcol-gateway
  namespace: monitoring
spec:
  selector:
    app: otelcol-gateway
  ports:
    - name: otlp-grpc
      port: 4317
  # No LoadBalancer needed — DaemonSet agents use loadbalancingexporter for consistent routing
  clusterIP: None  # Headless service: DNS returns all pod IPs for loadbalancing
```

## Service for App → Agent Communication

Applications should send OTLP to the DaemonSet agent on the same node using the node IP:

```yaml
# In application deployment
env:
  - name: K8S_NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://$(K8S_NODE_IP):4317"
```
