# RBAC — 최소권한 접근제어

**RBAC(Role-Based Access Control)** 는 "누가(subject) 무엇을(resource) 어떻게(verb) 할 수
있는가"를 정한다. **Role** 은 네임스페이스 안의 권한 묶음, **ClusterRole** 은 클러스터 전역
권한이고, **RoleBinding/ClusterRoleBinding** 이 그 권한을 사용자·그룹·**ServiceAccount** 에
붙인다. 핵심 원칙은 **최소권한** — 딱 필요한 것만 준다.

> 참고: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. ServiceAccount 생성

파드(앱)가 API 서버에 인증할 때 쓰는 신원인 **ServiceAccount** `deployer` 를 만든다.

ServiceAccount 생성:

```bash
kubectl create serviceaccount deployer
```

생성 확인:

```bash
kubectl get sa deployer
```

## 2. Role 과 RoleBinding

`pods` 를 **읽기만**(get/list/watch) 허용하는 Role `pod-reader` 를 만들고, RoleBinding
`read-pods` 로 그걸 `deployer` 에 붙인다.

Role 과 RoleBinding 생성:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: pod-reader, namespace: default }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: read-pods, namespace: default }
subjects:
  - { kind: ServiceAccount, name: deployer, namespace: default }
roleRef:
  { kind: Role, name: pod-reader, apiGroup: rbac.authorization.k8s.io }
EOF
```

RoleBinding 확인:

```bash
kubectl describe rolebinding read-pods
```

## 3. auth can-i 로 검증

`kubectl auth can-i ... --as=<주체>` 로 실제 권한을 시험한다. deployer 는 pods 를 **list 할 수
있어야**(yes) 하고, **delete 는 못 해야**(no) 한다.

주체 변수 설정:

```bash
SA=system:serviceaccount:default:deployer
```

pods list 권한 시험:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

pods delete 권한 시험:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

secrets list 권한 시험:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (Role 에 없음)
```

`list pods`→yes, `delete pods`→no 가 나오면 최소권한이 제대로 걸린 것이다.

> 참고: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
