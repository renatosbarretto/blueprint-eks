#!/usr/bin/env bash
# Bootstrap do bucket S3 de state (lock nativo do S3: use_lockfile, sem DynamoDB).
# Uso: TG_CLUSTER=lab-dev ./scripts/bootstrap-state.sh   (conta/região vêm do account.yaml)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TG_CLUSTER:?defina TG_CLUSTER (ex: export TG_CLUSTER=lab-dev)}"

python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --check-account

ACCOUNT_ID="$(python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --get account_id)"
REGION="$(python3 -I "${ROOT}/scripts/validate-cluster.py" "${TG_CLUSTER}" --get region)"
BUCKET="eks-blueprint-tfstate-${ACCOUNT_ID}"

echo "Account: ${ACCOUNT_ID}  Region: ${REGION}  Bucket: ${BUCKET}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket já existe: ${BUCKET}"
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  echo "Bucket criado: ${BUCKET}"
fi

# Idempotente: reaplica os controles a cada execução.
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
EOF
)"
aws s3api put-bucket-lifecycle-configuration --bucket "${BUCKET}" --lifecycle-configuration '{
  "Rules": [{
    "ID": "expire-old-state-versions",
    "Status": "Enabled",
    "Filter": {},
    "NoncurrentVersionExpiration": {"NoncurrentDays": 90, "NewerNoncurrentVersions": 10}
  }]
}'

echo "Bootstrap completo."
