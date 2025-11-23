Kubernetes Cluster Validation Script
A comprehensive Bash script for validating Kubernetes clusters and generating professional delivery reports.

📋 Overview
This script performs a thorough health check of a Kubernetes cluster, validating key components and producing a consolidated report for cluster delivery or health assessment. It checks:

Namespaces: Verifies namespace status (Active/Terminating)
Helm Releases: Validates the status of Helm deployments
Deployments: Ensures pods are ready and available
Pods: Checks health status, excluding completed jobs
Ingress URLs: Tests service endpoint accessibility
Flux Kustomizations: Verifies GitOps synchronization status
Nodes: Confirms node health and readiness
Istio: Detects service mesh version and status
The script generates a clean, professional report summarizing the cluster's health and identifying any issues.

� Prerequisites
Required Tools
kubectl: Kubernetes command-line tool (with valid kubeconfig access)
helm: Helm package manager for checking Helm releases
jq: JSON processor for parsing Kubernetes API responses
curl: For testing HTTP accessibility of ingress URLs
nslookup: For DNS resolution checks
Cluster Access
A valid kubeconfig file configured for the target cluster
Appropriate RBAC permissions to access namespaces, deployments, pods, ingress, and nodes
Optional: Access to Istio and Flux resources if deployed
🚀 Quick Start
Clone or download the script:

git clone <repository-url>  # If hosted in a repository
# OR
curl -O https://raw.githubusercontent.com/company/k8s-tools/cluster_validation.sh
Make the script executable:

chmod +x cluster_validation.sh
Run the script:

./cluster_validation.sh
View the results: The script outputs a detailed report to the terminal, including a professional delivery template and any identified issues.

📊 Sample Output
The script generates a formatted report like this:

╔══════════════════════════════════════════════════════════════════════════════════════╗
║                              CLUSTER DELIVERY TEMPLATE                               ║
╚══════════════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                CLUSTER INFORMATION                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Cluster Name        : my-k8s-cluster-prod                                          │
│ Cluster Version     : 1.31.12-eks-e386d34                                          │
│ Istio Version       : 1.24.2                                                       │
│ Namespaces          : (Active namespaces)                                          │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                SERVICE ENDPOINTS                                    │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Prometheus URL      : https://prometheus.example.com/                              │
│ Alert Manager URL   : https://alertmanager.example.com/                            │
│ Grafana URL         : https://grafana.example.com/                                 │
│ Dashboard URL       : https://dashboard.example.com/                               │
│ Thanos URL          : https://thanos.example.com/                                  │
│ Kiali URL           : https://kiali.example.com/                                   │
│ Vault URL           : (To be configured)                                           │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                VALIDATION SUMMARY                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ Component           │ Status     │ Healthy  │ Total    │ Issues   │
├─────────────────────┼────────────┼──────────┼──────────┼──────────┤
│ Namespaces          │ Active     │ 15       │ 15       │ 0        │
│ Helm Releases       │ Deployed   │ 38       │ 39       │ 1        │
│ Deployments         │ Ready      │ 29       │ 30       │ 1        │
│ Ingress URLs        │ Healthy    │ 8        │ 8        │ 0        │
│ Kustomizations      │ Ready      │ 1        │ 1        │ 0        │
└─────────────────────┴────────────┴──────────┴──────────┴──────────┘

🎉 OVERALL STATUS: ALL SYSTEMS HEALTHY - CLUSTER READY FOR DELIVERY! 🎉
If issues are found, a detailed breakdown is provided:

⚠️  OVERALL STATUS: 3 ISSUES FOUND - REVIEW REQUIRED ⚠️

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           🔍 DETAILED ISSUES BREAKDOWN                             │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ ❌ HELM RELEASES (1 issues):                                                       │
│    • prod/my-app: failed                                                           │
│                                                                                     │
│ ❌ DEPLOYMENTS (1 issues):                                                         │
│    • prod/my-app-deployment: Not Ready (1/2)                                      │
│                                                                                     │
│ ❌ INGRESS URLs (1 issues):                                                        │
│    • https://my-app.example.com/: Failed (503)                                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
🔧 Command Line Options
Option	Description	Example
-n, --namespace <NAMESPACE>	Check a specific namespace (default: all namespaces)	./cluster_validation.sh -n production
-c, --context <CONTEXT>	Use a specific kubectl context	./cluster_validation.sh -c my-cluster
-t, --timeout <SECONDS>	Set HTTP timeout for ingress checks (default: 10)	./cluster_validation.sh -t 15
-v, --verbose	Enable verbose output for detailed logs	./cluster_validation.sh -v
-h, --help	Display the help message	./cluster_validation.sh -h
Examples
Check all namespaces:

./cluster_validation.sh
Check a specific namespace with verbose output:

./cluster_validation.sh -n production -v
Use a specific context with a 15-second timeout:

./cluster_validation.sh -c my-cluster -t 15
🎯 Use Cases
Cluster Delivery: Validate newly deployed clusters before handing them over to teams
Health Monitoring: Perform regular health checks to ensure cluster stability
Troubleshooting: Identify and diagnose issues with specific cluster components
GitOps Validation: Verify Flux Kustomizations for GitOps-managed clusters
Service Mesh Verification: Confirm Istio installation and version
🔍 Validation Details
Namespaces
Checks the status of namespaces (Active or Terminating)
Reports total and active namespace counts
Helm Releases
Validates the deployment status of Helm releases
Identifies failed or pending releases
Deployments
Verifies pod readiness and availability
Reports replicas that are not ready or available
Pods
Checks pod health status (Running, Pending, Failed, etc.)
Excludes completed jobs (normal behavior for batch jobs)
Reports restarts and container readiness issues
Ingress URLs
Tests DNS resolution and HTTP accessibility for all ingress URLs
Assumes HTTPS protocol unless specified otherwise
Reports DNS and HTTP failures
Flux Kustomizations
Validates the synchronization status of Flux Kustomizations
Reports ready and failed Kustomizations
Nodes
Verifies node status (Ready or NotReady)
Reports node roles and versions
Istio
Detects the Istio version (if installed)
Checks the status of Istio pods in the istio-system namespace
📝 Notes
Temporary Files: The script creates temporary files in a directory (/tmp) to store intermediate results. These are automatically cleaned up upon script completion
Permissions: Ensure the user running the script has sufficient RBAC permissions to access all resources being validated
Dependencies: Missing dependencies (kubectl, helm, jq, curl, nslookup) will cause the script to fail or skip certain checks
Istio and Flux: These checks are optional and only run if the respective components are detected in the cluster
Verbose Mode: Use -v for detailed output, which is useful for debugging
🤝 Contributing
Contributions are welcome! To contribute:

Fork the repository (if hosted)
Create a feature branch (git checkout -b feature/new-feature)
Commit your changes (git commit -m "Add new feature")
Push to the branch (git push origin feature/new-feature)
Open a pull request
Please submit issues or enhancement requests via the repository's issue tracker.

⚠️ Troubleshooting
Permission Errors: Ensure your kubeconfig has the necessary permissions for kubectl get operations on namespaces, deployments, pods, ingress, nodes, and custom resources (Flux Kustomizations, Istio)
Missing Tools: Install kubectl, helm, jq, curl, and nslookup if not already present
DNS/HTTP Failures: Verify network connectivity and DNS resolution for ingress URLs. Adjust the timeout with -t if needed
Istio Not Detected: The script skips Istio checks if the istio-system namespace is not found
