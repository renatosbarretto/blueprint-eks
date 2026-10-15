# Análise: CoreDNS não agendou no Fargate

**Objetivo:** Identificar se falta algum selector ou tag que impeça o CoreDNS de ser agendado no perfil Fargate `coredns`.

---

## Atualização (correção aplicada)

- **Causa provável:** O profile passou a usar apenas a label `eks.amazonaws.com/component=coredns`. Em muitos clusters o add-on CoreDNS continua a usar a label **`k8s-app=kube-dns`** no pod template; nesse caso o selector não fazia match e o pod nunca era elegível para o Fargate.
- **Correção:** O Fargate profile "coredns" foi alterado para ter **dois selectors** (o pod agenda se coincidir com **qualquer um**):
  1. `namespace = "kube-system"` + `labels = { "k8s-app" = "kube-dns" }`
  2. `namespace = "kube-system"` + `labels = { "eks.amazonaws.com/component" = "coredns" }`
- Para diagnóstico no cluster: usar o script `scripts/diagnose-coredns-fargate.sh`.

---

## 1. Configuração atual

### 1.1 Fargate profile "coredns" (eks-cluster)

- **Ficheiro:** `terraform/modules/eks-cluster/main.tf`
- **Condição de criação:** `create_fargate_profile_for_kube_system = true` (quando `enable_karpenter && karpenter_on_fargate`).
- **Selectors (dois; match em qualquer um):**
  - `namespace = "kube-system"` + `labels = { "k8s-app" = "kube-dns" }`
  - `namespace = "kube-system"` + `labels = { "eks.amazonaws.com/component" = "coredns" }`
- **Subnets:** `var.private_subnet_ids` (as mesmas do cluster).
- **Tags do recurso:** `var.tags` (sem tag específica para EKS; o profile é associado ao cluster por `cluster_name`).

### 1.2 Add-on CoreDNS (eks-addons bootstrap)

- **Ficheiro:** `terraform/modules/eks-addons/main.tf`
- O add-on `coredns` é instalado sem `configuration_values`; a AWS usa o template padrão do add-on.
- O deployment fica em `kube-system` com nome típico `coredns`.

### 1.3 Patch no wait_for_coredns_on_fargate (main.tf)

- Remove **apenas** o nodeSelector com chave `kubernetes.io/os` do deployment `coredns`:
  - `kubectl patch deployment coredns -n kube-system --type=json -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/kubernetes.io~1os"}]'`
- Em seguida: delete dos pods `k8s-app=kube-dns`, depois `kubectl wait` no deployment.

---

## 2. Pontos que podem impedir o agendamento no Fargate

### 2.1 Labels do pod vs selector do Fargate profile

- O profile exige **namespace** `kube-system` e **label** `k8s-app=kube-dns`.
- A documentação AWS e o comportamento histórico do add-on CoreDNS assumem que o deployment usa `k8s-app: kube-dns` no pod template.
- Em versões mais recentes do add-on, a AWS pode usar ou adicionar outras labels (ex.: `eks.amazonaws.com/component: coredns`). Se o pod **não** tiver `k8s-app: kube-dns`, o selector do Fargate **não** faz match e o pod nunca será agendado no profile.
- **Conclusão:** É possível que o add-on atual (por versão ou configuração) não coloque `k8s-app=kube-dns` nos pods, ou use apenas outra label. Falta **confirmar no cluster** quais labels o deployment realmente define no `spec.template.metadata.labels`.

### 2.2 NodeSelector no deployment (patch incompleto)

- O único patch aplicado remove a chave `kubernetes.io/os` do `nodeSelector`.
- O add-on EKS pode definir outros nodeSelectors, por exemplo:
  - `node.kubernetes.io/os` (nome mais recente)
  - `beta.kubernetes.io/os` (legado)
  - Ou algo como `eks.amazonaws.com/compute-type: ec2` (hipótese), que forçaria apenas nós EC2 e excluiria Fargate.
- Se existir qualquer nodeSelector que só seja satisfeito por nós EC2 (e no bootstrap não há nós EC2), os pods ficam **Pending** e não vão para Fargate.
- **Conclusão:** O patch pode não estar a remover o nodeSelector que realmente bloqueia o Fargate. Falta **inspecionar** `spec.template.spec.nodeSelector` (e, se existir, `node.kubernetes.io/os` / `beta.kubernetes.io/os` / outros) **depois** do add-on instalado e, se aplicável, **depois** do patch.

### 2.3 Topology spread constraints (add-on recente)

- A documentação AWS indica que, em versões recentes do add-on CoreDNS (ex.: v1.9.3-eksbuild.11+), o deployment pode ter **topologySpreadConstraints** por zona (ex.: `topology.kubernetes.io/zone`) com `whenUnsatisfiable: ScheduleAnyway`.
- Com `ScheduleAnyway`, o scheduler não deve **bloquear** o agendamento; no máximo afeta a distribuição. Por isso é menos provável que seja a causa principal, a menos que exista alguma configuração com `DoNotSchedule` ou restrições adicionais que não estejam documentadas.
- **Conclusão:** Improvável como causa única, mas vale a pena ver no cluster se há topology spread (e com que `whenUnsatisfiable`) no deployment do CoreDNS.

### 2.4 Subnets e tags (VPC)

- O perfil Fargate usa `var.private_subnet_ids`; a VPC marca as subnets privadas com:
  - `kubernetes.io/cluster/${var.project_name}-${var.environment}` = `"shared"`
  - `kubernetes.io/role/internal-elb` = `"1"`.
- O nome do cluster no módulo EKS é `"${var.project_name}-${var.environment}"`, portanto a tag do cluster está alinhada com o nome do cluster.
- Para Fargate, a documentação AWS exige que as subnets usadas pelo profile tenham a tag do cluster; com `"shared"` isso está coberto.
- **Conclusão:** Não parece faltar tag nas subnets para o Fargate profile. Mantém-se a recomendação de confirmar no console/CLI que o profile está associado às subnets esperadas.

### 2.5 Nome do deployment e namespace

- O patch e o `kubectl wait` assumem deployment `coredns` no namespace `kube-system`. O add-on gerido pela AWS usa esse nome e namespace.
- **Conclusão:** Sem indício de incompatibilidade aqui.

### 2.6 Possível reaplicação do add-on (server-side apply)

- A AWS usa server-side apply nos add-ons. Após o nosso patch no deployment, o controlador do add-on EKS pode **reaplicar** o spec e repor nodeSelectors ou outras alterações que removemos.
- Nesse caso, os pods seriam recriados com o spec “oficial” do add-on e voltariam a ficar Pending se esse spec excluir Fargate.
- **Conclusão:** Pode existir uma “corrida” entre o nosso patch e o add-on. Vale verificar, após o apply e o patch, se o deployment mantém ou não o nodeSelector removido.

---

## 3. Resumo: o que pode estar a falhar

| Área | Hipótese | O que verificar |
|------|----------|------------------|
| **Selector do profile** | Pod do CoreDNS sem label `k8s-app=kube-dns` | `kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.metadata.labels}'` e ver se existe `k8s-app: kube-dns`. |
| **NodeSelector** | Outro nodeSelector (ex.: `node.kubernetes.io/os` ou `eks.amazonaws.com/compute-type`) a bloquear Fargate | `kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.nodeSelector}'` antes/depois do patch. |
| **Topology spread** | Restrições com `DoNotSchedule` ou exigências que Fargate não cumpre | `kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.topologySpreadConstraints}'`. |
| **Tags / subnets** | Profile ou subnets mal configurados | Console EKS → Cluster → Fargate profiles → profile "coredns" (subnets e status). |
| **Add-on a sobrescrever o patch** | Add-on a repor nodeSelector após o nosso patch | Repetir a leitura do deployment alguns segundos depois do patch e após recriação dos pods. |

---

## 4. Comandos sugeridos para diagnóstico (no cluster que falhou)

```bash
# Labels do pod template do CoreDNS (confirmar se k8s-app=kube-dns existe)
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.metadata.labels}' | jq .

# NodeSelector atual (ver o que realmente bloqueia)
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.nodeSelector}' | jq .

# Topology spread (se existir)
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' | jq .

# Eventos dos pods do CoreDNS (motivo de Pending)
kubectl get events -n kube-system --field-selector involvedObject.name=coredns-* --sort-by='.lastTimestamp'

# Descrição dos pods CoreDNS (Conditions e Events)
kubectl describe pods -n kube-system -l k8s-app=kube-dns
# ou, se a label for outra:
kubectl get pods -n kube-system -l eks.amazonaws.com/component=coredns -o wide
kubectl describe pod -n kube-system -l eks.amazonaws.com/component=coredns
```

---

## 5. Conclusão

- **Selector/tag:** O único selector do Fargate profile é `namespace=kube-system` + `k8s-app=kube-dns`. Não há outra tag no profile que precise de estar no pod; o risco é o **contrário**: o pod não ter essa label e por isso não fazer match com o profile.
- **Possíveis causas mais prováveis:** (1) pod do CoreDNS sem a label `k8s-app=kube-dns`; (2) nodeSelector no deployment diferente de `kubernetes.io/os` (ex.: `node.kubernetes.io/os` ou um que force EC2), deixando o patch atual sem efeito; (3) add-on a reaplicar o deployment e a anular o patch.
- **Próximo passo recomendado:** Correr os comandos de diagnóstico acima no cluster onde o CoreDNS não agendou e, com o resultado, decidir se é necessário: alargar o selector do Fargate profile a mais labels que o add-on realmente usa, ou alargar o patch para remover mais nodeSelectors (e eventualmente relaxar topology spread, se for o caso). **Nenhuma alteração foi feita no código nesta análise.**
