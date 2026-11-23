# Gateway API (lab-dev)

Pré-requisito: `enable_gateway_api: true` aplicado (LBC + CRDs + GatewayClass `aws-alb` / `aws-nlb`).

## Smoke ALB + HTTPRoute

```bash
kubectl apply -f examples/gateway-api/echo-alb.yaml
kubectl get gateway,httproute -A
kubectl get gateway public-alb -o jsonpath='{.status.addresses}\n'
```

Hostname de exemplo: `echo.dev.brttech.dev` (ExternalDNS cria o registro se o ALB estiver Programmed).
