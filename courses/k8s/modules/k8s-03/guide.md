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

내용 확인:

```bash
kubectl get cm app-config -o yaml
```

`kubectl describe cm app-config` 로 두 키가 들어갔는지 확인한다.

## 2. Secret 생성

키 `DB_PASSWORD` 를 가진 **Opaque** Secret `app-secret` 을 만든다. `create secret generic`
은 값을 자동으로 base64 인코딩한다.

Secret 생성:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

인코딩된 값 확인:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

디코딩해서 확인:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

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

Ready 될 때까지 대기:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

환경변수 확인:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → env
```

Secret 파일 확인:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → 파일
```

env 로 `APP_MODE`/`APP_GREETING` 이 보이고 `/etc/app-secret/DB_PASSWORD` 파일이 있으면 성공.

> 참고: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
