# Análise dos logs do Karpenter (controller)

Com base nos logs que partilhaste (`kubectl logs -n karpenter deployment/karpenter -c controller`), há **três pontos** relevantes:

---

## 1. ERROR: "karpenter version is not compatible with K8s version 1.34"

**Linha:** `"controller":"providers.version","error":"updating version, validating kubernetes version, karpenter version is not compatible with K8s version 1.34"`

**Causa provável:** O controller em execução não é reconhecido como compatível com Kubernetes 1.34. Isto pode acontecer se:
- A **imagem** em execução for antiga (ex.: 1.2.x ou 0.37) e o chart/Helm estiver em 1.9.0 (por upgrade só da variável sem redeploy do Helm), ou
- O chart não estiver a usar a tag de imagem alinhada à versão do chart.

**Correção aplicada no código:** No módulo Karpenter (`terraform/modules/karpenter/main.tf`) foi adicionado nos values do Helm:

```hcl
controller = {
  image = {
    tag = var.karpenter_version
  }
}
```

Assim, a imagem do controller fica explicitamente com a mesma versão do chart (ex.: 1.9.0), que suporta K8s 1.34. Após `terraform apply`, o Helm usa a imagem correta; se o deployment já existir, convém reiniciar o pod ou fazer upgrade do release para aplicar a nova imagem.

**Verificação:** Depois do apply, confirma a imagem em execução:
```bash
kubectl get deployment karpenter -n karpenter -o jsonpath='{.spec.template.spec.containers[?(@.name=="controller")].image}'
```
Deve ser algo como `.../karpenter:1.9.0`.

---

## 2. ERROR: "ignoring nodepool, not ready" / "no nodepools found"

**Linhas:** `"ignoring nodepool, not ready","NodePool":{"name":"default"}` e `"no nodepools found"`.

**Causa:** O NodePool `default` é considerado "not ready". Isto costuma estar ligado a:
- O controller `providers.version` falhar (versão incompatível com 1.34), o que pode deixar o sistema num estado em que o NodePool não fica ready, ou
- O EC2NodeClass `default` ainda não estar pronto (ex.: "no subnets found"), o que também impede o NodePool de ficar ready.

**Ação:** Resolver o ponto 1 (versão) e o ponto 3 (subnets). Depois disso, o NodePool tende a ficar ready e o provisioner volta a considerar o `default`.

---

## 3. ERROR: "failed listing instance types for default" / "no subnets found"

**Linha:** `"controller":"disruption","error":"no subnets found"`.

**Causa:** O EC2NodeClass `default` não está a encontrar subnets com o selector configurado. O template usa:

```yaml
subnetSelectorTerms:
  - tags:
      "kubernetes.io/role/internal-elb": "1"
```

A VPC do blueprint marca as subnets privadas com essa tag, por isso o selector está correto. O erro pode ser:
- **Transitório:** no arranque, o controller de disruption pode correr antes do EC2NodeClass ter terminado a reconciliação (subnets descobertas). Nos teus logs, mais à frente aparecem nodeclaims criados e nós lançados, o que indica que as subnets acabaram por ser encontradas.
- **IAM:** o controller já tem `ec2:DescribeSubnets` na policy; não é expectável que seja o problema.
- **Tags:** confirma no console AWS (EC2 > Subnets) que as subnets privadas do cluster têm a tag `kubernetes.io/role/internal-elb = 1`.

**Verificação:** Estado do EC2NodeClass e motivo de não estar pronto (se aplicável):
```bash
kubectl get ec2nodeclass default -o yaml
kubectl describe ec2nodeclass default
```

Se o status mostrar subnets encontradas e o NodePool ficar ready após os pontos 1 e 2, este erro de "no subnets found" pode deixar de aparecer ou ficar apenas como mensagem inicial.

---

## Resumo

| Problema | Causa provável | O que foi feito / o que fazer |
|----------|----------------|--------------------------------|
| Versão não compatível com 1.34 | Imagem do controller desalinhada do chart | Fixar `controller.image.tag` no Helm ao `karpenter_version` (1.9.0) e redeploy |
| NodePool "not ready" / "no nodepools found" | Consequência da versão ou do EC2NodeClass | Resolver versão e subnets; revalidar após apply |
| "no subnets found" | Transitório ou tags/EC2NodeClass | Confirmar tags nas subnets e status do EC2NodeClass; pode ser só no arranque |

Depois de aplicares o Terraform com a alteração da imagem e, se necessário, de reiniciares o deployment do Karpenter, volta a recolher os logs e o status do EC2NodeClass/NodePool para confirmar que estes erros deixaram de ocorrer.
