# argo-workflow-vault-integration

## Introduction
Argo Workflows is an open source project that is container-native and utilizes Kubernetes to run the workflow steps.  Argo enables users to create a multi-step workflow that can orchestrate parallel jobs and/or capture the dependencies between tasks.  The framework allows for parameterization and conditional execution, passing values between steps, timeouts, retry logic, recursion, flow control, and looping.

HashiCorp Vault is a secrets management tool specifically designed to control access to sensitive credentials in a low-trust environment.  Vault provides a unified interface to any secret, while providing tight access control and recording a detailed audit log.

Argo gives you a convenient way to access OpenShift secrets but what if your customer/company uses Vault instead?  I'll walk you through how to do this and package it up into a Helm chart for easy installation and reuse.

## Git Input Artifact
 Argo Workflows have a very convenient feature to easily get source code from git.  The GitArtifact allows for basic auth or SSH private key.  If you have your credentials stored in an OpenShift secret it is really easy to include.  See the [workflow-git-input-artifact.yaml](workflow-git-input-artifact.yaml) as an example.

 ## Argo & Vault
Since Argo does not have built-in support for Vault, we cannot use the GitArtifact described above.  Lucky for us, we can take advantage of Vault’s ability to mount files on the pod filesystem.  In the [workflow-git-vault.yaml](workflow-git-vault.yaml) example our Vault secret is a token and we take advantage of the Vault sidecar injector by annotating our workflow step.
