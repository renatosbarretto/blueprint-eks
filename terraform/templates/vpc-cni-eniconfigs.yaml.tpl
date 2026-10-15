# ENIConfigs para VPC CNI Custom Networking (rede secundária, ex.: 10.147.x)
# Um ENIConfig por AZ; o nome deve coincidir com a label topology.kubernetes.io/zone (ENI_CONFIG_LABEL_DEF)
%{for i, cfg in eniconfigs~}
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: ${cfg.az}
spec:
  subnet: ${cfg.subnet_id}
  securityGroups:
    - ${cluster_security_group_id}
%{endfor~}
