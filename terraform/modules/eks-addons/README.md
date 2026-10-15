# EKS Add-ons Module

Instala add-ons gerenciados EKS e metrics-server:
- **vpc-cni** – AWS VPC CNI
- **coredns** – CoreDNS
- **kube-proxy** – kube-proxy
- **aws-ebs-csi-driver** – EBS CSI com IRSA e opcional KMS
- **aws-efs-csi-driver** – opcional
- **metrics-server** – via Helm

Requer que o cluster EKS e o OIDC provider já existam.
