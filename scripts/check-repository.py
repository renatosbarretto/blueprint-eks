#!/usr/bin/env python3
"""Offline checks for publication artifacts and parseable example configs."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[1]
files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
errors = []
for name in files:
    path = ROOT / name
    if not path.is_file():
        continue
    if path.name in {"tfplan", "terraform.tfstate"} or path.suffix in {".tfplan", ".tfstate", ".tfvars", ".tfbackend"} or ".terraform" in path.parts:
        errors.append(f"Execution artifact in publication: {name}")
        continue
    text = path.read_text(errors="replace")
    # Values are intentionally never printed.
    patterns = [r"(?:AKIA|ASIA)[A-Z0-9]{16}", r"gh[pousr]_[A-Za-z0-9]{30,}", r"github_pat_[A-Za-z0-9_]{30,}", r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"]
    if any(re.search(pattern, text) for pattern in patterns):
        errors.append(f"Potential secret in {name}")
    if path.suffix in {".yaml", ".yml"}:
        list(yaml.safe_load_all(text))
    if path.suffix == ".json":
        json.loads(text)
# Use Terraform itself to parse all tfvars examples, without providers or backend.
with tempfile.TemporaryDirectory(prefix="eks-examples-") as temp:
    Path(temp, "variables.tf").write_text((ROOT / "terraform/variables.tf").read_text())
    for example in (ROOT / "terraform").rglob("*.tfvars.example"):
        result = subprocess.run(["terraform", f"-chdir={temp}", "console", f"-var-file={example}"], input="1\n", text=True, capture_output=True)
        if result.returncode:
            errors.append(f"Invalid example {example.relative_to(ROOT)}: {result.stderr}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"Publication checks passed ({len(files)} paths, examples, YAML and JSON).")
