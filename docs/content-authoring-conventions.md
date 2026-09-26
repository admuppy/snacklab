# 랩 콘텐츠 저작 규약 (Content Authoring Conventions)

SnackLab의 모든 트랙(Linux, KubeVirt, 향후 신규 트랙)의 `guide.md` / `guide.en.md`
작성 시 공통으로 지켜야 하는 규약. 새 과목을 만들 때 이 문서를 기준으로 삼는다.

## 참고문서 링크는 항상 새 창에서

가이드 본문의 **외부 참고문서 링크(`http(s)://`)는 항상 새 창/새 탭에서 열리도록**
한다. 학습자가 실습 세션(터미널 + 가이드 패널)을 떠나지 않고 참고자료를 볼 수 있어야
하기 때문이다. 랩 탭 자체가 참고문서로 덮이면 진행 중이던 세션·터미널 상태를 잃는다.

- 저작자는 그냥 평범한 마크다운 링크로 쓰면 된다: `[공식 문서](https://kubevirt.io/user-guide/)`
- 새 창 처리는 **포털이 렌더 시점에 자동으로** 수행한다 — 저작자가 HTML이나
  `target` 속성을 직접 넣을 필요 없음.
- 구현: `v0.1/public/lab.html`의 `renderGuide()`가 `marked.parse()` 직후
  본문 내 `href`가 `http(s):`인 `<a>`에 `target="_blank"` + `rel="noopener noreferrer"`를
  부여한다. 내부 `#앵커` 링크는 같은 창에서 이동(제외).
- 새 트랙/새 렌더 경로를 추가하더라도 이 동작을 유지할 것. 마크다운 렌더러를 교체하면
  동일한 후처리(외부 링크 새 창)를 반드시 재적용한다.

## 가이드 코드 블록 = 클릭 1회 = 명령 1줄 (2026-08-05)

lab.html 은 코드 블록 클릭 시 `pre.innerText` 전체를 터미널 WS 로 한 번에 보낸다. 여러 줄이면
앞 명령이 도는 동안 뒷줄이 씹힐 수 있다. 그래서 **학습형 트랙(linux·k8s) 가이드의 실행용 코드
블록은 블록당 셸 명령 1줄**로 쓴다.

- 블록 여러 개로 나누고, 각 블록 바로 위에 짧은 한 줄 캡션(끝에 `:`)을 단다. 캡션은 파일 언어를 따른다.
- 한 줄 안의 `&&` 연결은 그대로 둔다(이미 1줄). 줄을 쪼개서 합치지 않는다.
- **heredoc**(`cat <<EOF | kubectl apply -f -` … `EOF`)과 백슬래시 연속행은 논리적 1명령 — 한 블록 유지.
- 순수 YAML 예시·출력 예시·파일 내용 블록은 실행용이 아니므로 그대로 둔다.
- `## ` 섹션 수는 steps 수와 같아야 하므로 절대 변하면 안 된다.
- 시험형 트랙(cka·ckad·cks)은 실제 시험처럼 학습자가 명령을 스스로 구성해야 하므로 이 규약을 강제하지 않는다.

## 명령어 풀이 = 코드 블록 바로 뒤 목록 (2026-09-26)

학습형 트랙(linux·k8s·openstack) 가이드는 실행용 코드 블록 **바로 뒤에** 그 명령의 풀이를 목록으로 단다.
lab.html 이 `pre + ul` 을 보조 설명 스타일(작은 글씨·왼쪽 선)로 렌더하므로, 코드 블록과 목록 사이에는
빈 줄 하나만 두고 다른 문단을 끼우지 않는다.

~~~markdown
```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — YAML 없이 명령형으로 Deployment 를 만든다.
- `--replicas=3` — 항상 유지할 파드 수(`spec.replicas`).
~~~

- 항목 형식: `` `명령/옵션` — 설명 ``. 처음 보는 명령·옵션·셸 문법(`$( )`, `>>`, `2>&1`, 히어독 등)을 풀어 준다.
- 같은 모듈 안에서 이미 풀이한 명령이 다시 나오면 생략해도 된다(daemon-reload, rollout status 등).
- 종합(캡스톤) 모듈에서는 **해답을 풀이에 적지 않는다** — 주어진 진단 명령의 의미만 설명한다.
- `guide.md` 와 `guide.en.md` 에 같은 내용을 각 언어로 단다.
- 시험형 트랙은 해당 없음(명령을 스스로 구성하는 것이 연습).

## (기존) 스크립트 실행 규약 요약

- **pod 드라이버**(Linux 트랙 등): `bootstrap.sh` / `checks/*.sh` / `solution.sh`는
  pod 안 learner 계정으로 `kubectl exec ... su - learner -c 'bash -s'` stdin 실행.
  KUBECONFIG 불필요.
- **KubeVirt 드라이버**: 스크립트가 VM 안에서 SSH로 실행되므로
  `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` 필수(.bashrc 미적용).
- `bootstrap.sh`는 멱등, 제한 시간 내 완료.
- `guide.md`의 `## ` 섹션 수 = `meta.json`의 steps 수 (lab.html이 `## ` 기준으로 split).
- 다국어: `guide.md`(ko 원문) + `guide.<로케일>.md` (en·ja·zh-CN·zh-TW·es·de). 학습형 트랙(linux·k8s·openstack)은
  7개 로케일을 모두 둔다(2026-09-26). 번역본의 코드 블록은 주석을 제외하고 영문본과 **글자 그대로 같아야** 하고,
  `## ` 섹션 수·코드 블록 수·풀이 목록 위치·참고 링크도 같아야 한다. 가이드의 **[체크]** 버튼 이름은 각 로케일 UI 라벨
  (`public/i18n.js` 의 `check`: チェック·校验·驗證·Comprobar·Prüfen)을 따른다.
- meta.json 의 title/desc/steps[].title, checks/messages.json 도 같은 7개 로케일을 채운다(`{0}` 자리표시자 유지).

## 로케일 폴백 순서 (guide / explain / 콘텐츠 문자열)

파일: `<base>.<로케일>.md` → **원문 로케일(ko) 요청이면 `<base>.md`** → 같은 언어의 다른 지역 변형
(zh-TW → zh-CN) → `<base>.en.md` → `<base>.md`.
문자열(title/desc/steps[].title, checks/messages.json): 요청 로케일 → 같은 언어의 다른 변형 → en
→ 기본 로케일.

- 한국어 요청에서 `<base>.md` 를 먼저 보는 순서가 빠지면 **한국어 사용자에게 영어 가이드가
  나간다**(실제로 두 번 그런 상태였다). 새 폴백 경로를 만들 때 이 항목을 반드시 지킬 것.
- 확장자 없는 원문의 언어는 `SOURCE_LOCALE`(server.js, 기본 `ko`, env `CONTENT_SOURCE_LOCALE`)로 판정한다.
  **`DEFAULT_LOCALE`(포털 UI 기본값)로 판정하면 안 된다** — 운영 배포가 `DEFAULT_LOCALE=en` 이라
  한국어 사용자에게 `guide.en.md` 가 나가던 버그의 원인이었다(2026-09-26 수정).
- 미번역 로케일에 한국어 원문보다 영어를 주는 것이 의도다.
- 과목에 따라 **일부 로케일만 번역하는 것이 정답일 수 있다** — CKA 모의고사는 실제 시험이
  영어·일본어·중국어(간체)만 지원하므로 그 3종 + 한국어만 작성한다.

### 시험 언어 강제 (`meta.exam.languages`)

자격시험 모의고사는 **실제 시험이 제공하는 언어로 푸는 것이 연습**이다. 그래서 시험형 랩에는
시험이 지원하는 로케일 목록을 둔다.

```json
"exam": { "passPercent": 66, "languages": ["en", "ja", "zh-CN"] }
```

- 학습자 로케일이 목록에 없으면 **문항·채점 메시지·해설·랩 제목을 시험 언어로** 내린다
  (같은 언어의 변형이 목록에 있으면 그쪽 우선: zh-TW → zh-CN, 없으면 en). 포털 UI 언어는 그대로다.
- 랩에 처음 들어가면 **왜 그 언어로 나오는지 팝업으로 한 번** 안내한다(랩별 1회, localStorage).
- 학습자 로케일 번역본이 존재하면 팝업과 상단 버튼에서 **연습용으로 내 언어 보기**를 고를 수 있다
  → 이후 요청에 `?native=1` 이 붙어 강제가 풀린다(가이드·채점 양쪽 모두).
- `languages` 를 두지 않으면 종전대로 학습자 로케일을 그대로 쓴다(일반 랩은 영향 없음).

## 시험형 랩 (exam mode) — 제출·부분점수·해설

문항별 [체크] 대신 **[제출하고 채점하기] 한 번으로 전 문항을 일괄 채점**하는 랩. CKA 모의고사
(`courses/cka/modules/cka-01`)가 첫 사례다. 켜는 방법과 규약:

**meta.json**

```json
{
  "exam": { "passPercent": 66 },
  "steps": [ { "title": …, "points": 7, "check": "step1.sh" }, … ]
}
```

- `exam` 키가 있으면 포털이 시험 모드로 렌더한다(체크 버튼 숨김 → 제출 버튼).
- 시험형 랩은 **모든 step 에 `points` 필수**(없으면 모듈이 카탈로그에서 제외된다).
- 합격선 = `ceil(passPercent × 총배점 / 100)`. 기본값 66(실제 CKA 기준).

**부분점수 — `part` 헬퍼**

체크 스크립트는 채점 항목마다 `part <획득> <배점> <메시지키> [인자…]` 를 출력한다.
`labmsg` 와 같은 규약이며 포털이 `checks/messages.json` 으로 로케일 렌더링한다.

```bash
if kubectl get sa deploy-bot -n app-prod >/dev/null 2>&1; then part 1 1 q1c1; else part 0 1 step1m1; fi
```

- **앞 항목이 틀려도 exit 하지 말고 끝까지 채점**한다(스크립트는 항상 `exit 0`).
- 어느 분기로 흘러도 `part` 의 **배점 합계는 meta 의 `points` 와 같아야 한다**.
  전제 조건(리소스 자체가 없음)이 깨지면 뒤 항목들을 `part 0 <배점> <실패키>` 로 한 번씩 내보낸다.
- 통과 항목은 "무엇을 맞혔는지" 라벨 키(`q1c1`…), 실패 항목은 기존 FAIL 메시지 키를 쓴다.
- `part` 줄이 하나도 없는 스크립트는 종료코드로 통과/실패를 가리는 기존 방식 그대로 동작한다
  (통과 시 해당 문항 만점).

**해설 — `explain.md` / `explain.en.md`**

- `guide.md` 와 같은 규칙: `## ` 섹션 수 = steps 수, 순서도 문항 순서와 같다.
- 포털은 **제출 응답에서만, 만점을 못 받은 문항의 섹션만** 내려보낸다. 제출 전에는 어떤 API 로도
  노출되지 않으므로 정답을 그대로 적어도 된다.
- 화면에서는 가이드 본문 맨 아래 "틀린 문항 해설" 블록으로 붙고, 지금 보고 있는 문항만 펼쳐진다.

**뱃지**

기준 점수만 넘기면 만점이 아니어도 모듈 이수 뱃지를 준다(트랙 완주 판정도 동일). 재제출 가능하며
`progress.json` 에는 최고 점수(`exam.best`)와 시도 횟수가 남는다.
