# argocd-bootstrap

Installs Argo CD with Helm and creates the root Application that syncs `gitops/environments/<env>`. It also registers
the Karpenter OCI chart repository and the Application health check that makes sync waves wait. This is the only
Kubernetes state Terraform owns.

Tests: `tests/argocd-bootstrap.tftest.hcl` (mocked provider, runs offline with `terraform test`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0 |
| helm | >= 3.0, < 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| helm | >= 3.0, < 4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.argocd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.root](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment folder under gitops/environments that the root Application syncs. | `string` | n/a | yes |
| repo\_url | HTTPS URL of the Git repository Argo CD reads. | `string` | n/a | yes |
| argocd\_apps\_chart\_version | Version of the argocd-apps Helm chart that creates the root Application. | `string` | `"2.0.5"` | no |
| argocd\_chart\_version | Version of the argo-cd Helm chart. | `string` | `"10.9.2"` | no |
| namespace | Namespace for Argo CD and its Application objects. | `string` | `"argocd"` | no |
| target\_revision | Branch, tag or commit the root Application tracks. | `string` | `"main"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| argocd\_namespace | Namespace where Argo CD runs. |
| root\_application\_path | Repository path the root Application syncs. |
<!-- END_TF_DOCS -->
