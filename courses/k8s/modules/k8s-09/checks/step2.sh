#!/bin/bash
# step2: default-deny(ingress) 정책이 web 을 대상으로 존재하고, client → web 이 실제로 차단되는지
#
# 순서 독립성: 3단계에서 허용 정책(web-allow-client)을 추가하면 통신이 다시 열리는 것이 정상이다.
# 그때 이 체크가 FAIL 로 뒤집히지 않도록, 허용 정책이 이미 있으면 "정책 형태(웹 선택 + 빈 ingress)"
# 까지만 확인한다. 허용 정책이 없을 때만 실제 차단을 요구한다.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get netpol default-deny -n default -o json > /tmp/np.json 2>/dev/null \
  || { labmsg step2m1; exit 1; }
jq -e '(.spec.policyTypes // []) | index("Ingress")' /tmp/np.json >/dev/null \
  || { labmsg step2m2; exit 1; }
jq -e '.spec.podSelector.matchLabels.app == "web"' /tmp/np.json >/dev/null \
  || { labmsg step2m3; exit 1; }
jq -e '(.spec.ingress // []) | length == 0' /tmp/np.json >/dev/null \
  || { labmsg step2m4; exit 1; }

# 3단계의 허용 정책이 이미 있으면 통신이 열려 있는 것이 정상 — 차단 여부는 검사하지 않는다.
if kubectl get netpol -n default -o json \
     | jq -e '[.items[] | select(.metadata.name != "default-deny") | select((.spec.ingress // []) | length > 0)] | length > 0' >/dev/null 2>&1; then
  labmsg step2m5
  exit 0
fi
if kubectl exec client -n default -- wget -q -T 3 -t 1 -O- http://web >/dev/null 2>&1; then
  labmsg step2m6; exit 1
fi
labmsg step2m7
