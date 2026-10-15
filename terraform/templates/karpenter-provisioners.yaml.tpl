# NodePool: requisitos de instance types e referência à EC2NodeClass.
# Em v1.9: expireAfter fica em spec.template.spec; disruption tem consolidateAfter (obrigatório) e consolidationPolicy.
# Doc: https://karpenter.sh/docs/concepts/nodepools/
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: In
          values: ["3", "4", "5", "6", "7"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      # Duração máxima de vida do nó (v1.9: em template.spec, não em disruption).
      expireAfter: 720h
  limits:
    cpu: "1000"
  disruption:
    consolidateAfter: 30s
    consolidationPolicy: WhenEmptyOrUnderutilized
---
# EC2NodeClass: descoberta de subnets/SG/AMI e configuração de nós.
# Melhores práticas: karpenter.sh/discovery para SG, metadataOptions, blockDeviceMappings.
# Doc: https://karpenter.sh/docs/concepts/nodeclasses/
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: ${ami_alias}
  # instanceProfile pré-provisionado pelo Terraform (evita IAM endpoint em VPC privada).
  instanceProfile: ${instance_profile_name}
  subnetSelectorTerms:
%{ for subnet_id in subnet_ids ~}
    - id: ${subnet_id}
%{ endfor ~}
  # karpenter.sh/discovery recomendado pela doc (evita conflito com AWS Load Balancer Controller).
  securityGroupSelectorTerms:
    - tags:
        "karpenter.sh/discovery": "${cluster_name}"
  # IMDS seguro (recomendado pela doc e security best practices).
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1
    httpTokens: required
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: ${node_volume_size}Gi
        volumeType: ${node_volume_type}
        iops: ${node_volume_iops}
        throughput: ${node_volume_throughput}
        encrypted: ${encrypted}
%{if ebs_kms_key_arn != ""}
        kmsKeyID: "${ebs_kms_key_arn}"
%{endif}
        deleteOnTermination: true
