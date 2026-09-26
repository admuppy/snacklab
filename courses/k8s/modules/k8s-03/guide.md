# ConfigMap 과 Secret

설정과 코드는 분리하는 게 원칙이다. **ConfigMap** 은 평문 설정을, **Secret** 은 비밀번호·토큰
같은 민감정보를 (base64 로 인코딩해) 담아 파드에 **환경변수** 나 **볼륨 파일** 로 주입한다.

> 참고: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. ConfigMap 생성

키 `APP_MODE`, `APP_GREETING` 을 가진 ConfigMap `app-config` 를 만든다.

ConfigMap 생성:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — ConfigMap `app-config` 를 명령형으로 만든다. 줄 끝 `\` 는 한 명령을 여러 줄로 이어 쓴 것.
- `--from-literal=키=값` — 키/값 쌍을 직접 넣는다. 여러 번 줄 수 있고, 공백이 든 값은 따옴표로 감싼다.
- 파일로 만들 땐 `--from-file=<경로>`, env 파일은 `--from-env-file=<경로>` 를 쓴다.

내용 확인:

```bash
kubectl get cm app-config -o yaml
```

- `cm` 은 `configmap` 의 축약형. `-o yaml` 로 저장된 원본(`data:` 아래 키/값)을 그대로 본다.

`kubectl describe cm app-config` 로 두 키가 들어갔는지 확인한다.

## 2. Secret 생성

키 `DB_PASSWORD` 를 가진 **Opaque** Secret `app-secret` 을 만든다. `create secret generic`
은 값을 자동으로 base64 인코딩한다.

Secret 생성:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — 임의 키/값용 `Opaque` 타입 Secret 을 만든다. (그 밖에 `tls`, `docker-registry` 타입이 있다.)
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — 값은 저장 시 자동으로 base64 인코딩된다. 작은따옴표는 셸 특수문자 해석을 막는다.

인코딩된 값 확인:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — Secret 의 `data` 필드 중 한 키의 값(base64 문자열)만 뽑는다.

디코딩해서 확인:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — base64 를 디코딩(`-d`)해 원래 값을 보여 준다. 즉 Secret 을 읽을 권한만 있으면 누구나 평문을 볼 수 있다.

> 참고: Secret 의 data 는 인코딩일 뿐 암호화가 아니다. 실제 운영에선 etcd 암호화·RBAC 로
> 접근을 제한한다 — [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. 파드에서 주입 소비

파드 `app` 을 만들어 **ConfigMap 을 환경변수(envFrom)** 로, **Secret 을 볼륨 파일**
(`/etc/app-secret`)로 주입한다.

파드 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - { name: secret-vol, mountPath: /etc/app-secret, readOnly: true }
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `envFrom.configMapRef` — ConfigMap 의 **모든 키**를 같은 이름의 환경변수로 주입한다. (한 키만 쓰려면 `env[].valueFrom.configMapKeyRef`.)
- `volumes[].secret` + `volumeMounts` — Secret 의 각 키를 `/etc/app-secret/<키>` 파일로 마운트한다.

Ready 될 때까지 대기:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — 파드의 `Ready` 조건이 참이 될 때까지 기다린다.
- `--timeout=60s` — 그 시간 안에 안 되면 실패로 끝난다.

환경변수 확인:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → env
```

- `kubectl exec app -- <명령>` — 실행 중인 컨테이너 안에서 명령을 실행한다. `--` 뒤가 컨테이너에서 돌 명령.
- `printenv A B` — 지정한 환경변수 값만 출력한다.

Secret 파일 확인:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → 파일
```

- 볼륨으로 마운트한 Secret 은 이미 디코딩된 평문 파일로 보인다. 키 이름이 곧 파일 이름이다.

env 로 `APP_MODE`/`APP_GREETING` 이 보이고 `/etc/app-secret/DB_PASSWORD` 파일이 있으면 성공.

> 참고: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
