# argo-workflow-vault-integration

## Introduction
Argo Workflows is an open source project that is container-native and utilizes Kubernetes to run the workflow steps.  Argo enables users to create a multi-step workflow that can orchestrate parallel jobs and/or capture the dependencies between tasks.  The framework allows for parameterization and conditional execution, passing values between steps, timeouts, retry logic, recursion, flow control, and looping.

HashiCorp Vault is a secrets management tool specifically designed to control access to sensitive credentials in a low-trust environment.  Vault provides a unified interface to any secret, while providing tight access control and recording a detailed audit log.

Argo gives you a convenient way to access OpenShift secrets but what if your customer/company uses Vault instead?  I'll walk you through how to do this and package it up into a Helm chart for easy installation and reuse.

## Setup
### Argo installation on OpenShift
Argo workflow install documentation can be found [here](https://argoproj.github.io/argo/installation/).  However, it is very easy to install and consists of 3 steps.<br/>

1. Create a project for Argo.
```
oc new-project argo
```

2. Apply namespace-install.yaml
```
oc apply -n argo -f https://raw.githubusercontent.com/argoproj/argo/stable/manifests/namespace-install.yaml
```

3. Update argo workflow config map
```
oc edit cm workflow-controller-configmap
```
Add the following at the bottom of the file and save it.
```
data:
  config: |
    containerRuntimeExecutor: pns
```

For ease of use we are going to grant the argo SA cluster admin rights.  You wouldn't want to do this in production.
```
oc create rolebinding argo-admin --clusterrole=admin --serviceaccount=argo:argo
```

### Vault installtion on OpenShift
Vault install documentation can be found [here](https://learn.hashicorp.com/tutorials/vault/kubernetes-openshift?in=vault/kubernetes).  Some basic steps needed for these workflows are as follows:

Create a vault namespace
```
oc new-project vault
```

Add the vault helm chart repo
```
helm repo add hashicorp https://helm.releases.hashicorp.com
```

Run the vault helm chart
```
helm install vault hashicorp/vault \
     --set "global.openshift=true" \
     --set "server.dev.enabled=true"
```

Connect to the vault pod to configure
```
oc exec -it vault-0 -- /bin/sh
```

Enable kubernetes auth
```
vault auth enable kubernetes
```

Configure the Kubernetes authentication method to use the service account token, the location of the Kubernetes host, and its certificate.
```
vault write auth/kubernetes/config \
     token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

Create your `git-creds` secret
```
vault kv put secret/git-creds token="YOUR_TOKEN_HERE"
```

Define a read policy so we can read the secret
```
vault policy write git-creds - <<EOF
 path "secret/data/git-creds" {
   capabilities = ["read"]
 }
EOF
```

Create a Kubernetes authentication role, named `git-creds`, that connects the Kubernetes service account `argo` and the `git-creds` policy.
```
vault write auth/kubernetes/role/git-creds \
     bound_service_account_names=argo \
     bound_service_account_namespaces=argo \
     policies=git-creds \
     ttl=24h
```

## Creating Argo Workflows
You can use the [Argo CLI](https://argoproj.github.io/argo/cli/) to install the workflows or the Argo UI.  In order to use the UI you will need to create a route to access the UI.  Below is a sample route you could use:
```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: argo-wf-ui
  namespace: argo
spec:
  to:
    kind: Service
    name: argo-server
    weight: 100
  port:
    targetPort: 2746
  wildcardPolicy: None
```

### Git Input Artifact
 Argo Workflows have a very convenient feature to easily get source code from git.  The GitArtifact allows for basic auth or SSH private key.  If you have your credentials stored in an OpenShift secret it is really easy to include.  See the [workflow-git-input-artifact.yaml](workflow-git-input-artifact.yaml) as an example.  In order to run this workflow you will need to create a Secret named `git-creds` in the `argo` namespace.
 ```
 oc create secret generic git-creds \
   --from-literal=username=YOUR_USERNAME \
   --from-literal=password=YOUR_PASSWORD
 ```

 ### Argo & Vault
Since Argo does not have built-in support for Vault, we cannot use the GitArtifact described above.  Lucky for us, we can take advantage of Vault’s ability to mount files on the pod filesystem.  In the [workflow-git-vault.yaml](workflow-git-vault.yaml) example our Vault secret is a token and we take advantage of the Vault sidecar injector by annotating our workflow step.

In the [workflow-git-vault-push.yaml](workflow-git-vault-push.yaml) workflow we utilize the directed-acyclic graph (dag) option to define our workflow steps.  We have 2 steps 
```
      git-clone
         |
         |
      git-push
```
The git-clone step utilizes the vault sidecar injector to get our git token and clone our repo.  We pass that same token as a parameter to the `git-push` step to add a new file to our repo and take advantage of `VolumeClaimTemplates` in order to persist the cloned repo onto a shared volume that can be used by any step in the workflow.

### Helm
You can install all of the workflows utilizing the helm chart found in the [helm](helm) folder.  You can run the following to get the workflows installed
```
helm install my-workflows . --set git.repo=YOUR_REPO_HERE
```
If you look in the [templates](helm/templates) folder you will notice a difference from the workflows in the root of this repo.  Since Argo utilizes the double curly bracket just like Helm as a template directive, we need to "escape" Argo's parameters.  If we did not escape them, Helm would attempt to inject a value, resulting in an empty string instead of the intended Argo parameter.  There are other ways to escape the double curly braces, but I find the printf function to be the cleanest solution.
```yaml
git:
  repo: '{{ printf "https://{{workflow.parameters.git-repo-url}}" }}'
            
```