# Análise: Pods do ArgoCD não sobem

## Resumo executivo

Os pods do ArgoCD não sobem por **duas causas que se reforçam**:

1. **VPC CNI (custom networking)** – Em nós EC2 (129 e 64), parte dos pods recebe IP da rede 10.147, mas outros falham com `failed to assign an IP address to container`. Isso indica **esgotamento de IPs por nó** (poucos endereços por ENI na subnet secundária), não falha total do CNI.
2. **Capacidade de agendamento** – Só há **2 nós EC2 agendáveis** (129 e 64), cada um com **máximo 8 pods** (ex.: c7a.medium). Esses nós estão **cheios** (8/8). Os restantes nós estão em cordon/drain (118, 119, 126) ou são Fargate com taint. Por isso muitos pods ficam em **Pending** com `0/8 nodes are available: 2 Too many pods, 3 node(s) had untolerated taint(s), 3 node(s) were unschedulable`.

Ou seja: onde há lugar para agendar, o nó enche e o CNI deixa de conseguir atribuir IP a todos; onde não há lugar, os pods nem chegam a ser agendados.

---

## 1. Estado atual (evidências)

### 1.1 Nós

| Nó | Estado | Agendável? | Pods (cap/allocatable) |
|----|--------|------------|------------------------|
| ip-10-0-12-129.ec2.internal | Ready | Sim | 8 / 8 (cheio) |
| ip-10-0-12-64.ec2.internal  | Ready | Sim | 8 / 8 (cheio) |
| ip-10-0-12-118/119/126       | NotReady,SchedulingDisabled | Não (drenados) | - |
| 3× Fargate                   | Ready | Não (taint `fargate:NoSchedule`) | 1 pod cada |

Só os dois nós EC2 (129 e 64) aceitam pods “normais”. Cada um tem **capacity.pods = 8** (típico de instâncias pequenas, ex.: c7a.medium).

### 1.2 Pods ArgoCD

- **Pending** (sem nó): application-controller-0, applicationset (replica nova), dex-server, redis (replica nova), repo-server (replica nova), server (replica nova) – evento: `0/8 nodes available: 2 Too many pods, 3 had untolerated taint(s), 3 unschedulable`.
- **ContainerCreating / Init:0/1** (já agendados em 129 ou 64): applicationset (hxkz2), notifications-controller, redis (5nsxl), repo-server (2gmmp) – evento: `Failed to create pod sandbox: plugin type="aws-cni" ... failed to assign an IP address to container`.

Ou seja: quem consegue agendar fica preso no CNI; quem não consegue fica em Pending por falta de nós com slot.

### 1.3 O que funciona no mesmo nó

No nó **129** estão **Running**: aws-node, ebs-csi-node, kube-proxy, aws-load-balancer-controller, metrics-server (5 pods). Ou seja, o CNI **consegue** atribuir IP a vários pods; depois passa a falhar para os seguintes. Isso indica **limite de IPs por nó** (ENI/secondary IP na subnet 10.147), não falha global do custom networking nem necessariamente falta de IRSA.

### 1.4 IRSA no aws-node

A ServiceAccount `aws-node` tem a anotação `eks.amazonaws.com/role-arn`. Nos nós 129 e 64, os pods do aws-node **não** exibem essa anotação no `metadata.annotations` (possível diferença de momento de criação ou de injeção). O CNI nesses nós pode estar a usar a role da instância (Karpenter node role, que tem `AmazonEKS_CNI_Policy`). O problema observado é sobretudo **quantidade de IPs por nó**, não só permissões.

---

## 2. Causas (cruzamento)

| Causa | Onde aparece | Impacto |
|-------|--------------|--------|
| **Max pods = 8 por nó** | `capacity.pods` / `allocatable.pods` = 8 em 129 e 64 | Poucos “slots” por nó; nós enchem rápido; muitos ArgoCD pods ficam Pending. |
| **Poucos IPs por ENI (custom networking)** | Eventos `failed to assign an IP address to container` em pods já agendados em 129/64 | Depois de ~5 pods com IP no nó, o CNI deixa de atribuir mais; pods ficam em ContainerCreating/Init. |
| **Apenas 2 nós agendáveis** | 3 nós em cordon, 3 Fargate com taint | Toda a carga de ArgoCD + sistema compete por 2×8 = 16 slots. |
| **Nós drenados ainda no cluster** | 118, 119, 126 em NotReady,SchedulingDisabled | Contam como “unschedulable”; não recebem novos pods; reduzem opções de agendamento. |

Conclusão: não é um único bug do ArgoCD (nem só do Helm). É a combinação de **limite de pods por nó (8)**, **limite de IPs por nó no custom networking** e **poucos nós agendáveis**.

---

## 3. Dependências do ArgoCD (contexto)

- **application-controller** (StatefulSet) – núcleo do control loop.
- **repo-server** – init container (ex.: copiar bins); depois container principal.
- **redis** – usado pelo application-controller e repo-server.
- **server**, **dex-server**, **applicationset-controller**, **notifications-controller** – dependem indiretamente do controller e do repo-server.

Enquanto redis, repo-server e application-controller não tiverem IP e não estiverem Ready, o resto não completa. Ou seja: o problema não é a ordem de deploy do ArgoCD em si, é **rede (IP) e capacidade (slots)**.

---

## 4. Ações recomendadas (por prioridade)

### 4.1 Remover nós drenados do cluster (rápido)

Os nós 118, 119, 126 já foram drenados e estão NotReady. Remover do API server liberta “conta” de nós e evita confusão no scheduler:

```bash
kubectl delete node ip-10-0-12-118.ec2.internal ip-10-0-12-119.ec2.internal ip-10-0-12-126.ec2.internal
```

Assim o Karpenter pode passar a considerar apenas 2 EC2 + 3 Fargate e provisionar novos nós se houver Pending.

### 4.2 Aumentar IPs por nó (custom networking) – prefix delegation

Com custom networking na 10.147, cada ENI tem um número limitado de IPs secundários. Para aumentar o número de pods por nó sem mudar de instance type:

- **VPC CNI**: ativar **prefix delegation** (cada ENI passa a ter um prefixo /28, mais IPs por ENI).
- **EKS / bootstrap**: garantir que o add-on do VPC CNI está com a configuração que ativa prefix delegation (e, se aplicável, que o Karpenter/AMI não limita o kubelet a 8 pods).

Documentação: [Increase IP addresses for EKS (prefix delegation)](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html).

### 4.3 Aumentar max pods por nó (Karpenter / node config)

Hoje os nós têm **8** pods (allocatable). Para suportar mais workloads (ArgoCD + sistema):

- No **EC2NodeClass** (ou no userData da AMI usada pelo Karpenter), configurar o kubelet com `--max-pods` maior (ex.: 110), **e**
- Garantir que o CNI consegue atribuir tantos IPs (prefix delegation ou instance types com mais ENIs).

Assim os 2 nós (ou os que o Karpenter criar) passam a ter mais “slots” e menos “Too many pods”.

### 4.4 Garantir IRSA no aws-node nos nós novos

Para custom networking, o ideal é o aws-node usar a role IRSA (não só a role da instância):

- Confirmar que a SA `aws-node` tem `eks.amazonaws.com/role-arn` (já confirmado).
- Nos nós 129 e 64, forçar recriação dos pods do aws-node para que levem a anotação:
  ```bash
  kubectl delete pod -n kube-system -l app.kubernetes.io/name=aws-node --field-selector spec.nodeName=ip-10-0-12-129.ec2.internal
  kubectl delete pod -n kube-system -l app.kubernetes.io/name=aws-node --field-selector spec.nodeName=ip-10-0-12-64.ec2.internal
  ```
- Depois verificar se os novos pods do aws-node têm a anotação e se o CNI continua a atribuir IPs (e se o limite sobe com prefix delegation).

### 4.5 Mais nós EC2 (Karpenter)

Com apenas 2 nós EC2 e 8 pods cada, 16 slots não chegam para sistema + ArgoCD. Opções:

- **Deixar o Karpenter criar mais nós**: após apagar os nós 118/119/126, os pods Pending devem fazer o Karpenter provisionar novos NodeClaims (se o NodePool/EC2NodeClass e limites de conta o permitirem).
- **Aumentar o número de réplicas ou tamanho de instância** no NodePool (ex.: instance size ou range que permita mais pods por nó ou mais nós).

---

## 5. Verificações úteis

```bash
# Pods por nó (129 e 64)
kubectl get pods -A --field-selector spec.nodeName=ip-10-0-12-129.ec2.internal --no-headers | wc -l
kubectl get pods -A --field-selector spec.nodeName=ip-10-0-12-64.ec2.internal --no-headers | wc -l

# Eventos ArgoCD
kubectl get events -n argocd --sort-by='.lastTimestamp' | tail -30

# Descrição de um pod preso em ContainerCreating
kubectl describe pod -n argocd argocd-repo-server-6c7d6f75d5-2gmmp | tail -25
```

---

## 6. Conclusão

Os pods do ArgoCD não sobem porque:

1. **Poucos nós agendáveis** (2 EC2) com **poucos slots por nó (8)** → muitos Pending com “Too many pods”.
2. **Poucos IPs por nó** no custom networking (10.147) → pods já agendados ficam em ContainerCreating/Init com “failed to assign an IP”.

Resolver passa por: **remover nós drenados**, **aumentar IPs por nó (prefix delegation)** e **aumentar max pods por nó** (e, se necessário, mais nós via Karpenter). Em paralelo, manter **IRSA no aws-node** e validar que os novos pods do aws-node a usam.
