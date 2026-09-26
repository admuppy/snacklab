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

- `kubectl create serviceaccount <이름>` — 현재 네임스페이스(`default`)에 ServiceAccount 를 만든다. 파드는 `spec.serviceAccountName` 으로 이 신원을 쓴다.
- 새 ServiceAccount 는 처음엔 아무 권한이 없다 — 권한은 RoleBinding 으로 붙인다.

생성 확인:

```bash
kubectl get sa deployer
```

- `sa` 는 `serviceaccount` 의 축약형.

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

- `cat <<'EOF' | kubectl apply -f -` — `EOF` 줄까지의 YAML 을 표준입력으로 넘겨 적용한다. `-f -` 는 "파일 대신 stdin", 따옴표 친 `'EOF'` 는 본문의 `$` 를 셸이 치환하지 않게 한다.
- `---` — 한 번의 apply 로 여러 오브젝트(Role, RoleBinding)를 함께 만든다.
- `rules[].apiGroups: [""]` — 코어 API 그룹(pods, services, secrets 등). `resources` — 대상 리소스, `verbs` — 허용 동작.
- `subjects` — 권한을 받을 주체(여기선 ServiceAccount), `roleRef` — 연결할 Role. `roleRef` 는 만든 뒤 바꿀 수 없다.

RoleBinding 확인:

```bash
kubectl describe rolebinding read-pods
```

- 어떤 Role 이(`Role:`) 어떤 주체에게(`Subjects:`) 연결됐는지 한눈에 보여 준다.

## 3. auth can-i 로 검증

`kubectl auth can-i ... --as=<주체>` 로 실제 권한을 시험한다. deployer 는 pods 를 **list 할 수
있어야**(yes) 하고, **delete 는 못 해야**(no) 한다.

주체 변수 설정:

```bash
SA=system:serviceaccount:default:deployer
```

- ServiceAccount 의 사용자 이름은 `system:serviceaccount:<네임스페이스>:<이름>` 형식이다. 긴 이름을 셸 변수 `SA` 에 담아 둔다.

pods list 권한 시험:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <동사> <리소스>` — 해당 요청이 허용되는지 `yes`/`no` 로 답한다.
- `--as=$SA` — 관리자 권한 대신 지정한 주체인 척(impersonate) 해서 검사한다.

pods delete 권한 시험:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` 는 Role 의 `verbs` 에 없으므로 `no` 가 나와야 한다.

secrets list 권한 시험:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (Role 에 없음)
```

- Role 은 `pods` 만 다루므로 다른 리소스(`secrets`)는 동사와 상관없이 `no`. 전체 권한 목록은 `kubectl auth can-i --list --as=$SA` 로 볼 수 있다.

`list pods`→yes, `delete pods`→no 가 나오면 최소권한이 제대로 걸린 것이다.

> 참고: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
