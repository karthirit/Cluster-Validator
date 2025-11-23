Kubernetes Cluster Validation & Delivery Handover Script
k8s-cluster-validate.sh
A comprehensive, production-grade Bash script that performs a full health check of a Kubernetes cluster and automatically generates a clean, professional Cluster Delivery Handover Template ready to be sent to application teams, customers, or auditors.
Features

Checks all major components in one run:
Namespaces (Active/Terminating)
Helm releases (deployed vs failed/pending)
Deployments (ready replicas)
Pods (Running, Pending, Failed, CrashLoopBackOff, etc.)
Nodes status
Flux Kustomizations (if Flux is installed)
Istio version and control-plane health
All Ingress URLs → live HTTP + DNS connectivity test

Color-coded, emoji-rich console output
Consolidated beautiful ASCII boxed report with:
Cluster metadata (name, version, Istio version)
Key service endpoints (Prometheus, Alertmanager, Grafana, Kiali, etc.) – auto-discovered from healthy Ingresses
Summary table of healthy vs total resources
Detailed list of every problem found
Final verdict: ALL SYSTEMS HEALTHY or ISSUES FOUND – REVIEW REQUIRED

Supports checking a single namespace or the entire cluster
Works with custom kube contexts
Configurable HTTP timeout for Ingress checks

Use Cases

Pre-delivery validation before handing a cluster to application teams
Post-install verification of platform components (monitoring, logging, service mesh)
Periodic health checks in CI/CD or on-call runbooks
Audit-ready handover documentation

Prerequisites
Bash# Core tools
kubectl
helm
jq
curl
nslookup (or dig)

# Optional (only if you use them)
fluxctl   # only needed if you have Flux v2 Kustomizations
istioctl  # not required – script uses pilot-discovery directly
Usage
Bash# 1. Make it executable
chmod +x k8s-cluster-validate.sh

# 2. Run against current context (all namespaces)
./k8s-cluster-validate.sh

# 3. Common options
./k8s-cluster-validate.sh -n production          # only production namespace
./k8s-cluster-validate.sh -c prod-cluster        # specific kube context
./k8s-cluster-validate.sh -t 15                   # 15-second timeout for HTTP checks
./k8s-cluster-validate.sh -v                      # verbose output
./k8s-cluster-validate.sh -n monitoring -v       # verbose + single namespace

# 4. Get help
./k8s-cluster-validate.sh -h
Sample Output (truncated)
textStarting Kubernetes Cluster Validation

Cluster: prod-cluster-01
Cluster version: 1.29.8

Checking Namespaces
✅ Namespace default: Active
✅ Namespace kube-system: Active
✅ Namespace monitoring: Active
...

Checking Ingress URLs
[1/8] Testing: https://prometheus.example.com
 DNS: prometheus.example.com resolved
 HTTP: 200 (DNS resolved, service reachable)
[2/8] Testing: https://grafana.example.com
...

╔══════════════════════════════════════════════════════════════════════════════════════╗
║                              CLUSTER DELIVERY TEMPLATE                              ║
╚══════════════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ CLUSTER INFORMATION                                                                 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Cluster Name        : prod-cluster-01                                               │
│ Cluster Version     : 1.29.8                                                        │
│ Istio Version       : 1.20.3                                                        │
│ Namespaces          : (Product team namespaces only)                                │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ SERVICE ENDPOINTS                                                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Prometheus URL      : https://prometheus.example.com                                │
│ Alert Manager URL   : https://alertmanager.example.com                              │
│ Grafana URL         : https://grafana.example.com                                  │
│ Kiali URL           : https://kiali.example.com                                    │
│ Vault URL           : (To be configured)                                           │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ VALIDATION SUMMARY                                                                  │
├─────────────────────┼────────────┼──────────┼──────────┼──────────┤
│ Component           │ Status     │ Healthy  │ Total    │ Issues   │
├─────────────────────┼────────────┼──────────┼──────────┼──────────┤
│ Namespaces          │ Active     │ 18       │ 18       │ 0        │
│ Helm Releases       │ Deployed   │ 42       │ 42       │ 0        │
│ Deployments         │ Ready      │ 98       │ 98       │ 0        │
│ Ingress URLs        │ Healthy    │ 8        8        0        │
│ Kustomizations      │ Ready      │ 12       │ 12       │ 0        │
└─────────────────────┴────────────┴──────────┴──────────┴──────────┘

ALL SYSTEMS HEALTHY - CLUSTER READY FOR DELIVERY!
