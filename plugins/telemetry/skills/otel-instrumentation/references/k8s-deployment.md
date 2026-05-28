# Kubernetes OTel Deployment Reference

Shared reference for injecting Kubernetes metadata into OTel resource attributes via the Downward API. Used by all `otel-<lang>` skills for Kubernetes deployments.

> **Last verified:** 2026-03-22

## Why the Downward API?

The OTel `k8s_attributes` Collector processor enriches telemetry with Kubernetes metadata. For it to work, the app must expose `k8s.pod.uid` as a resource attribute — the processor uses this to look up additional metadata from the Kubernetes API.

Attributes like `k8s.pod.name` and `k8s.node.name` are also useful for direct querying even without the Collector processor.

## Complete Pod Spec (Downward API)

```yaml
spec:
  containers:
    - name: order-service        # Use your actual container name here
      image: order-service:latest
      env:
        # === OTel Service Identity ===
        - name: OTEL_SERVICE_NAME
          value: "order-service"

        # === Build/Deploy Context ===
        - name: SERVICE_VERSION
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['app.kubernetes.io/version']
        - name: ENVIRONMENT
          value: "production"     # Or from ConfigMap/Secret

        # === OTel Resource Attributes ===
        # Inject k8s metadata via Downward API
        - name: K8S_POD_UID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        - name: K8S_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: K8S_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName

        # Combine into OTEL_RESOURCE_ATTRIBUTES
        # All referenced vars (SERVICE_VERSION, ENVIRONMENT, K8S_*) must be defined above this entry
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.version=$(SERVICE_VERSION),deployment.environment.name=$(ENVIRONMENT),k8s.pod.uid=$(K8S_POD_UID),k8s.pod.name=$(K8S_POD_NAME),k8s.node.name=$(K8S_NODE_NAME),k8s.container.name=order-service"

        # === OTLP Endpoint (DaemonSet Collector on same node) ===
        # The DaemonSet agent is deployed via the Tsuga Helm chart (otel-collector/references/helm-chart.md).
        # The chart sets agent.hostNetwork: true, so the agent binds to the node IP — the endpoint below is correct.
        - name: K8S_NODE_IP
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://$(K8S_NODE_IP):4317"
```

## Attribute Injection Explained

| Attribute | Source | Why |
|-----------|--------|-----|
| `service.name` | `OTEL_SERVICE_NAME` env var | Required by OTel; identifies the service |
| `service.version` | Label `app.kubernetes.io/version` | Resolved at deploy time via label |
| `deployment.environment.name` | Hardcoded or ConfigMap | Identifies prod/staging/dev |
| `k8s.pod.uid` | `metadata.uid` via Downward API | **Critical**: used by `k8s_attributes` Collector processor |
| `k8s.pod.name` | `metadata.name` via Downward API | Per-pod debugging |
| `k8s.node.name` | `spec.nodeName` via Downward API | Node-level correlation |
| `k8s.container.name` | Hardcoded (no Downward API field) | Must match pod spec container name exactly |

## What the Collector Adds (Do NOT set in app)

The `k8s_attributes` Collector processor adds these automatically — do not duplicate them in app resource attributes:

- `k8s.deployment.name` — from Kubernetes API
- `k8s.namespace.name` — from Kubernetes API
- `k8s.cluster.name` — from Collector config
- `k8s.replicaset.name` — from Kubernetes API

## Notes on k8s.container.name

There is no Downward API field for the container name. You must hardcode it as a literal value matching the pod spec `containers[].name` field.

**BAD:**
```yaml
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.container.name=$(HOSTNAME)"  # HOSTNAME is not the container name
```

**GOOD:**
```yaml
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.container.name=order-service"  # Must match containers[].name in the same pod spec
```

## Notes on service.instance.id

For most Kubernetes deployments, `k8s.pod.uid` serves the same purpose as `service.instance.id` (uniquely identifying a running instance). You can either:

1. **Use pod UID directly as service.instance.id:**
   ```yaml
   - name: OTEL_RESOURCE_ATTRIBUTES
     value: "service.instance.id=$(K8S_POD_UID),k8s.pod.uid=$(K8S_POD_UID)"
   ```

2. **Generate UUID v4 at startup** (in SDK init code):
   ```
   // In your SDK initialization:
   serviceInstanceId = uuid.NewV4().String()
   ```

Both approaches are valid. Pod UID is simpler and directly correlatable with Kubernetes.
