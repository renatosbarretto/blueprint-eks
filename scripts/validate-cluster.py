#!/usr/bin/env python3
"""Valida cartões de cluster.

Layout: live/clusters/<ambiente>/<conta>/account.yaml + <cluster>.yaml
Merge (igual ao root.hcl): globals.defaults ← account.yaml ← <cluster>.yaml,
com cluster_name / environment / account_name vindos do caminho.

Uso:
  scripts/validate-cluster.py                          # todos os clusters
  scripts/validate-cluster.py lab-dev                  # um cluster
  scripts/validate-cluster.py lab-dev --check-account  # + confere credenciais AWS
  scripts/validate-cluster.py lab-dev --get region     # imprime um campo resolvido
"""
import argparse
import ipaddress
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
LIVE = ROOT / "live"
CLUSTERS = LIVE / "clusters"

ENVIRONMENTS = {"dev", "hml", "prd"}
NAME_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
ACCESS_POLICIES = {"view", "edit", "admin"}

# Vêm do caminho; não podem aparecer nos YAMLs.
DERIVED = {"cluster_name", "environment", "account_name"}

ACCOUNT_REQUIRED = ["account_id", "region"]
ACCOUNT_ALLOWED = {"account_id", "region", "availability_zones", "domain_name",
                   "route53_hosted_zone_id", "route53_assume_role_arn", "access_entries", "extra_tags"}

# Chaves que todo cluster declara explicitamente (versões e componentes visíveis no cartão).
CLUSTER_REQUIRED = [
    "vpc_cidr", "cluster_version", "karpenter_version", "karpenter_ami_alias",
    "eks_addon_versions", "chart_versions", "gateway_api_version",
]

# Addon EKS → flag que o habilita (None = sempre criado com o cluster).
EKS_ADDONS = {
    "vpc-cni": None,
    "kube-proxy": None,
    "coredns": None,
    "eks-pod-identity-agent": None,
    "aws-ebs-csi-driver": "enable_ebs_csi",
    "metrics-server": "enable_metrics_server",
    "eks-node-monitoring-agent": "enable_node_monitoring_agent",
    "amazon-cloudwatch-observability": "enable_cloudwatch_observability",
}

# Chart Helm → flag que o habilita.
CHARTS = {
    "aws_load_balancer_controller": "enable_gateway_api",
    "external_dns": "enable_external_dns",
    "external_secrets": "enable_external_secrets",
    "argocd": "enable_argocd",
}


def load(path):
    with open(path) as f:
        return yaml.safe_load(f) or {}


def discover():
    """{cluster_name: Path do yaml do cluster}; erros de layout em lista."""
    found, errors = {}, []
    for path in sorted(CLUSTERS.glob("*/*/*.yaml")):
        if path.name == "account.yaml":
            continue
        name = path.stem
        if name in found:
            errors.append(f"cluster {name} duplicado: {found[name]} e {path}")
        found[name] = path
    for path in CLUSTERS.glob("*/*.yaml"):
        errors.append(f"{path}: fora do layout <ambiente>/<conta>/<cluster>.yaml")
    return found, errors


def resolve(path, globals_):
    env, account = path.parent.parent.name, path.parent.name
    account_raw = load(path.parent / "account.yaml") if (path.parent / "account.yaml").exists() else None
    raw = load(path)
    card = {**globals_.get("defaults", {}), **(account_raw or {}), **raw,
            "cluster_name": path.stem, "environment": env, "account_name": account}
    return card, account_raw, raw


def validate(name, path, globals_, errors):
    def err(msg):
        errors.append(f"{name}: {msg}")

    card, account_raw, raw = resolve(path, globals_)
    defaults = globals_.get("defaults", {})

    # --- Layout / identidade ---
    if card["environment"] not in ENVIRONMENTS:
        err(f"pasta de ambiente '{card['environment']}' inválida (use {sorted(ENVIRONMENTS)})")
    if not NAME_RE.fullmatch(card["account_name"]):
        err(f"pasta da conta '{card['account_name']}' deve ser DNS-1123")
    if not NAME_RE.fullmatch(name) or len(name) > 30:
        err("nome do arquivo (= cluster_name) deve ser DNS-1123 com até 30 chars")

    # --- account.yaml ---
    if account_raw is None:
        err(f"{path.parent}/account.yaml ausente")
        account_raw = {}
    for key in ACCOUNT_REQUIRED:
        if key not in account_raw:
            err(f"account.yaml: chave obrigatória ausente: {key}")
    for key in sorted(set(account_raw) - ACCOUNT_ALLOWED):
        err(f"account.yaml: chave '{key}' não pertence à conta (mova para o cluster)")
    if not re.fullmatch(r"\d{12}", str(card.get("account_id", ""))):
        err("account_id deve ter 12 dígitos (entre aspas no YAML)")

    # --- cluster ---
    for key in sorted(DERIVED & (set(raw) | set(account_raw))):
        err(f"'{key}' vem do caminho (pasta/arquivo); remova do YAML")
    for key in CLUSTER_REQUIRED:
        if key not in raw:
            err(f"chave obrigatória ausente no cluster: {key}")
    for key in sorted(k for k in defaults if k.startswith("enable_")):
        if key not in raw:
            err(f"declare {key}: true|false no cluster")
    for key in sorted(set(raw) - set(defaults) - set(CLUSTER_REQUIRED) - DERIVED - {"access_entries"}):
        err(f"chave desconhecida (typo?): {key} — declare o default em live/globals.yaml")

    addon_versions = raw.get("eks_addon_versions") or {}
    for addon, flag in EKS_ADDONS.items():
        if (flag is None or card.get(flag)) and addon not in addon_versions:
            err(f"eks_addon_versions.{addon} ausente (addon habilitado)")
    for addon in sorted(set(addon_versions) - set(EKS_ADDONS)):
        err(f"eks_addon_versions.{addon}: addon desconhecido")

    charts = raw.get("chart_versions") or {}
    for chart, flag in CHARTS.items():
        if card.get(flag) and chart not in charts:
            err(f"chart_versions.{chart} ausente ({flag}: true)")

    net = None
    try:
        net = ipaddress.ip_network(card["vpc_cidr"])
        if not 16 <= net.prefixlen <= 18:
            err(f"vpc_cidr {net} deve ser /16 a /18")
    except (KeyError, ValueError) as e:
        err(f"vpc_cidr inválido: {e}")

    if card.get("nat_gateway_mode") not in ("single", "per_az"):
        err("nat_gateway_mode deve ser single ou per_az")

    alias = str(card.get("karpenter_ami_alias", ""))
    if not re.fullmatch(r"[a-z0-9]+@(latest|v\d{8})", alias):
        err(f"karpenter_ami_alias inválido: {alias}")
    if card["environment"] == "prd":
        if alias.endswith("@latest"):
            err("prd não pode usar karpenter_ami_alias @latest (fixe a versão)")
        if not card.get("deletion_protection"):
            err("prd deve ter deletion_protection: true")
        if card.get("nat_gateway_mode") != "per_az":
            err("prd deve usar nat_gateway_mode: per_az")

    if card.get("enable_external_dns"):
        for d in ("domain_name", "route53_hosted_zone_id"):
            if not card.get(d):
                err(f"enable_external_dns: true exige {d} (account.yaml)")

    seen_ns = {}
    for t in card.get("tenants") or []:
        tname = t.get("name", "")
        if not NAME_RE.fullmatch(tname) or len(tname) > 20:
            err(f"tenant '{tname}': nome DNS-1123 com até 20 chars (vira nome de role IAM)")
        if not t.get("namespaces"):
            err(f"tenant '{tname}': namespaces obrigatório")
        for ns in t.get("namespaces") or []:
            if ns in seen_ns:
                err(f"namespace '{ns}' em dois tenants ({seen_ns[ns]}, {tname})")
            seen_ns[ns] = tname
        if t.get("principal_arn") and t.get("sso_permission_set"):
            err(f"tenant '{tname}': use principal_arn OU sso_permission_set")
        if t.get("access_policy", "edit") not in ACCESS_POLICIES:
            err(f"tenant '{tname}': access_policy deve ser {sorted(ACCESS_POLICIES)}")

    entries = ((globals_.get("access_entries") or []) + (account_raw.get("access_entries") or [])
               + (raw.get("access_entries") or []))
    if not entries:
        err("nenhuma access_entry de admin — cluster ficaria inacessível")
    for e in entries:
        if not (e.get("principal_arn") or e.get("sso_permission_set")):
            err(f"access_entry '{e.get('name')}': precisa de principal_arn ou sso_permission_set")

    return card, net


def check_account(card, errors):
    try:
        out = subprocess.run(
            ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        errors.append(f"não foi possível obter a conta AWS atual: {e}")
        return
    if out != str(card["account_id"]):
        errors.append(f"{card['cluster_name']}: credenciais AWS são da conta {out}, "
                      f"conta {card['account_name']} exige {card['account_id']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clusters", nargs="*")
    ap.add_argument("--check-account", action="store_true")
    ap.add_argument("--get", metavar="KEY")
    args = ap.parse_args()

    globals_ = load(LIVE / "globals.yaml")
    found, errors = discover()

    for name in args.clusters:
        if name not in found:
            errors.append(f"cluster {name} não encontrado em live/clusters/<ambiente>/<conta>/{name}.yaml")
    names = args.clusters or sorted(found)

    if args.get:
        if len(names) != 1 or names[0] not in found:
            sys.exit("--get exige exatamente um cluster existente")
        card, _, _ = resolve(found[names[0]], globals_)
        print(card[args.get])
        return

    nets = {}
    for name in names:
        if name not in found:
            continue
        card, net = validate(name, found[name], globals_, errors)
        if net:
            nets[name] = (card, net)
        if args.check_account:
            check_account(card, errors)

    # VPCs na mesma conta não podem se sobrepor (peering / TGW no futuro).
    items = list(nets.items())
    for i, (a, (ca, na)) in enumerate(items):
        for b, (cb, nb) in items[i + 1:]:
            if str(ca.get("account_id")) == str(cb.get("account_id")) and na.overlaps(nb):
                errors.append(f"vpc_cidr de {a} ({na}) sobrepõe {b} ({nb})")

    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"PASS: {', '.join(names)}")


if __name__ == "__main__":
    main()
