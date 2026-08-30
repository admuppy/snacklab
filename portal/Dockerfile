# SnackLab 포털 이미지 (snacklab-portal)
# 빌드 컨텍스트 = 리포지토리 루트. kaniko: --dockerfile=portal/Dockerfile --context=tar://stdin
# 런타임: node server.js (WORKDIR /app/prototype). pod/kubevirt 드라이버가 kubectl 사용,
# 웹터미널 브리지가 python3(ptybridge.py) 사용.
FROM node:22-bookworm-slim

ARG KUBECTL_VERSION=v1.31.5
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl python3 \
 && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && apt-get purge -y curl && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app/prototype

# 의존성 레이어 (소스보다 먼저 — 캐시 활용)
COPY prototype/package.json prototype/package-lock.json ./
RUN npm ci --omit=dev

# 앱 소스 + 학습자 리소스 템플릿
COPY prototype/ ./
COPY deploy/ /app/deploy/

# 세션 상태 볼륨 마운트 지점 (helm이 PVC를 여기 마운트)
RUN mkdir -p /app/prototype/sessions

CMD ["node", "server.js"]
