#!/usr/bin/env bash
# SnackLab — 코스 번들(course.json + modules/) E2E 검증
#
# 포털을 거치지 않고 학습자 파드를 직접 띄워, 모듈마다
#   bootstrap.sh → (solution 전) 체크 전부 FAIL 이어야 함 → solution.sh → 체크 전부 PASS
# 를 확인한다. 실행 경로는 포털 pod 드라이버와 동일:
#   kubectl exec -i -n <ns> <pod> -- su - learner -c 'bash -s'   (stdin 으로 스크립트 주입)
#
# 사용:
#   ./deploy/e2e-course.sh courses/k8s                 # 전체 모듈
#   ./deploy/e2e-course.sh courses/k8s k8s-01 k8s-07   # 지정 모듈만
#   KEEP=1 ./deploy/e2e-course.sh courses/k8s k8s-01   # 실패 조사용으로 파드 보존
#
# 모듈마다 **새 파드**를 쓴다(세션=일회용 클러스터라는 실제 조건과 동일, 잔재로 인한 거짓 PASS 방지).
set -uo pipefail
cd "$(dirname "$0")/.."

COURSE_DIR=${1:?"사용: $0 <course-dir> [module-id ...]"}; shift || true
NS=${NS:-snacklab}
TEMPLATE=deploy/learner-pod.template.yaml
KEEP=${KEEP:-0}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-300}      # 파드 Ready 대기(초)
BOOTSTRAP_TIMEOUT=${BOOTSTRAP_TIMEOUT:-300}
CHECK_TIMEOUT=${CHECK_TIMEOUT:-30}

command -v jq >/dev/null || { echo "jq 필요"; exit 1; }
COURSE_JSON=$COURSE_DIR/course.json

if [ -f "$COURSE_JSON" ]; then
  # 코스 번들(courses/<id>/): 환경 이미지·리소스를 course.json 이 선언한다
  MODULES_DIR=$COURSE_DIR/modules
  IMAGE=${IMAGE:-$(jq -r '.image' "$COURSE_JSON")}
  HOST_MODULES=$(jq -r '.hostModules // false' "$COURSE_JSON")
  CLUSTER_INIT=$(jq -r '.clusterInit // false' "$COURSE_JSON")   # true → k3s embedded etcd (포털 pod 드라이버와 동일)
  CPU_REQ=$(jq -r '.resources.requests.cpu // "500m"' "$COURSE_JSON")
  MEM_REQ=$(jq -r '.resources.requests.memory // "1Gi"' "$COURSE_JSON")
  CPU_LIM=$(jq -r '.resources.limits.cpu // "2"' "$COURSE_JSON")
  MEM_LIM=$(jq -r '.resources.limits.memory // "4Gi"' "$COURSE_JSON")
  EPH_REQ=$(jq -r '.resources.requests["ephemeral-storage"] // "2Gi"' "$COURSE_JSON")
  EPH_LIM=$(jq -r '.resources.limits["ephemeral-storage"] // "8Gi"' "$COURSE_JSON")
  DEFAULT_MODULES=$(jq -r '.modules[]' "$COURSE_JSON")
else
  # 내장 콘텐츠(v0.1/content/): 기본 학습자 이미지로 돈다. 이미지는 IMAGE 로 지정/덮어쓰기.
  #   IMAGE=<registry>/snacklab-linux:v3 ./deploy/e2e-course.sh v0.1/content linux-01
  [ -d "$COURSE_DIR" ] || { echo "디렉터리 없음: $COURSE_DIR"; exit 1; }
  MODULES_DIR=$COURSE_DIR
  IMAGE=${IMAGE:?"course.json 이 없는 디렉터리 — IMAGE 환경변수로 학습자 이미지를 지정하세요"}
  HOST_MODULES=${HOST_MODULES:-false}
  CLUSTER_INIT=${CLUSTER_INIT:-false}
  CPU_REQ=${CPU_REQ:-250m}; MEM_REQ=${MEM_REQ:-256Mi}
  CPU_LIM=${CPU_LIM:-2};    MEM_LIM=${MEM_LIM:-2Gi}
  EPH_REQ=${EPH_REQ:-2Gi};  EPH_LIM=${EPH_LIM:-8Gi}
  DEFAULT_MODULES=$(ls -d "$MODULES_DIR"/*/ 2>/dev/null | xargs -n1 basename | grep -vE '^(module-|kubevirt-)' )
fi

MODULES=("$@")
if [ ${#MODULES[@]} -eq 0 ]; then
  mapfile -t MODULES < <(echo "$DEFAULT_MODULES")
fi

EXTRA_MOUNTS=""; EXTRA_VOLUMES=""
if [ "$HOST_MODULES" = true ]; then
  EXTRA_MOUNTS='        - { name: host-modules, mountPath: /lib/modules, readOnly: true }'
  EXTRA_VOLUMES='    - { name: host-modules, hostPath: { path: /lib/modules, type: Directory } }'
fi

# 체크 스크립트는 메시지를 키로만 내보낸다(labmsg / 부분점수는 part) — 포털이 하듯 프리앰블을
# 앞에 붙여 실행하고, 출력은 모듈의 checks/messages.json 으로 ko 렌더링해서 사람이 읽게 한다.
CHECK_PREAMBLE=$'labmsg() { printf \'\\001labmsg\'; for __a in "$@"; do printf \'\\001%s\' "$__a"; done; printf \'\\n\'; }\n'
CHECK_PREAMBLE+=$'part() { printf \'\\001labpart\\001%s\\001%s\' "$1" "$2"; shift 2; for __a in "$@"; do printf \'\\001%s\' "$__a"; done; printf \'\\n\'; }\n'

# 렌더링된 본문 + 마지막 줄에 `__SCORE__ <획득> <배점>` (part 줄이 없으면 `__SCORE__ - -`)
# 스크립트를 heredoc 이 아니라 -c 로 넘기는 것이 중요하다 — heredoc 은 stdin 을 먹어버려
# 정작 읽어야 할 체크 출력이 EOF 로 보인다(예전엔 렌더링 결과가 통째로 비어 있었다).
PY_RENDER=$(cat <<'PY'
import json, os, re, sys
cat = json.load(open(sys.argv[1], encoding='utf-8')) if os.path.exists(sys.argv[1]) else {}
def render(key, args):
    tpl = (cat.get(key) or {}).get('ko', key)
    return re.sub(r'\{(\d+)\}', lambda m: args[int(m.group(1))] if int(m.group(1)) < len(args) else m.group(0), tpl)
earned = total = 0
scored = False
for line in sys.stdin.read().split('\n'):
    i = line.find('\x01labpart\x01')
    if i >= 0:
        e, m, key, *args = line[i + 9:].split('\x01')
        earned += int(e or 0); total += int(m or 0); scored = True
        print(f"{line[:i]}    {'✓' if e == m else '✗'} {e}/{m} {render(key, args)}")
        continue
    i = line.find('\x01labmsg\x01')
    if i >= 0:
        key, *args = line[i + 8:].split('\x01')
        line = line[:i] + render(key, args)
    print(line)
print(f"__SCORE__ {earned} {total}" if scored else "__SCORE__ - -")
PY
)
render_msgs() { # stdin → 렌더링된 출력 ($1=모듈 디렉터리)
  python3 -c "$PY_RENDER" "$1/checks/messages.json"
}

# 파드 안에서 stdin 스크립트 실행 (포털과 동일 경로). 종료코드 = 스크립트 종료코드.
# 부분점수 스크립트는 항상 exit 0 이므로 종료코드로는 판정할 수 없다. 실행 결과는 전역에 남긴다:
#   RUN_OUT          렌더링된 출력
#   SCORE_E/SCORE_M  획득/배점 (part 줄이 없는 구형 스크립트는 빈 값)
# 출력을 표준출력으로 흘리지 않는 이유: 호출부가 out=$(run_in_pod …) 로 받으면 서브셸이라
# 점수 변수가 부모로 돌아오지 않는다(전부 직전 실행의 점수로 판정되는 버그가 났었다).
SCORE_E=""; SCORE_M=""; RUN_OUT=""
run_in_pod() { # $1=pod $2=script $3=timeout [$4=모듈 디렉터리(메시지 렌더링용)]
  local rc score
  out_raw=$( { printf '%s' "$CHECK_PREAMBLE"; cat "$2"; } \
    | timeout "$3" kubectl exec -i -n "$NS" "$1" -- su - learner -c 'bash -s' 2>&1 )
  rc=$?
  RUN_OUT=$(printf '%s' "$out_raw" | render_msgs "${4:-$2}")
  score=${RUN_OUT##*$'\n'__SCORE__ }
  if [ "$score" != "$RUN_OUT" ]; then
    SCORE_E=${score%% *}; SCORE_M=${score##* }
    [ "$SCORE_E" = "-" ] && { SCORE_E=""; SCORE_M=""; }
    RUN_OUT=${RUN_OUT%$'\n'__SCORE__ *}
  else
    SCORE_E=""; SCORE_M=""
  fi
  return $rc
}

new_pod() { # $1=pod 이름
  sed -e "s/__NAME__/$1/g" -e "s/__KIND__/e2e-pod/g" -e "s/__NS__/$NS/g" \
      -e "s#__IMAGE__#$IMAGE#g" -e "s/__CLUSTER_INIT__/$CLUSTER_INIT/g" \
      -e "s/__CPU_REQ__/$CPU_REQ/g" -e "s/__MEM_REQ__/$MEM_REQ/g" \
      -e "s/__CPU_LIM__/$CPU_LIM/g" -e "s/__MEM_LIM__/$MEM_LIM/g" \
      -e "s/__EPH_REQ__/$EPH_REQ/g" -e "s/__EPH_LIM__/$EPH_LIM/g" \
      -e "s#__EXTRA_MOUNTS__#$EXTRA_MOUNTS#g" -e "s#__EXTRA_VOLUMES__#$EXTRA_VOLUMES#g" \
      "$TEMPLATE" | kubectl apply -f - >/dev/null
  kubectl wait --for=condition=Ready "pod/$1" -n "$NS" --timeout="${BOOT_TIMEOUT}s" >/dev/null
}

FAILED=(); PASSED=()
for M in "${MODULES[@]}"; do
  MDIR=$MODULES_DIR/$M
  [ -d "$MDIR" ] || { echo "!! $M: 모듈 디렉터리 없음"; FAILED+=("$M(디렉터리)"); continue; }
  POD="e2e-$(echo "$M" | tr '[:upper:]_' '[:lower:]-')-$RANDOM"
  echo "=== $M (pod=$POD) ==="
  ok=1

  if ! new_pod "$POD"; then
    echo "  !! 파드 Ready 실패"; FAILED+=("$M(boot)")
    [ "$KEEP" = 1 ] || kubectl delete pod "$POD" -n "$NS" --wait=false >/dev/null 2>&1
    continue
  fi

  if [ -f "$MDIR/bootstrap.sh" ]; then
    t0=$(date +%s)
    if run_in_pod "$POD" "$MDIR/bootstrap.sh" "$BOOTSTRAP_TIMEOUT" "$MDIR"; then
      echo "  bootstrap: OK ($(( $(date +%s) - t0 ))s)"
    else
      echo "  bootstrap: FAIL ($(( $(date +%s) - t0 ))s)"; echo "$RUN_OUT" | tail -5 | sed 's/^/    /'; ok=0
    fi
  fi

  mapfile -t CHECKS < <(ls "$MDIR"/checks/step*.sh 2>/dev/null | sort)
  # ① solution 전: 체크가 전부 FAIL(부분점수 스크립트는 만점 미만)이어야 체크가 유의미하다
  if [ "$ok" = 1 ]; then
    for c in "${CHECKS[@]}"; do
      rc=0; run_in_pod "$POD" "$c" "$CHECK_TIMEOUT" "$MDIR" || rc=$?
      if [ -n "$SCORE_M" ]; then
        [ "$SCORE_E" = "$SCORE_M" ] && { echo "  pre-check $(basename "$c"): 만점($SCORE_E/$SCORE_M) — 체크가 무의미(거짓 PASS)"; ok=0; }
      elif [ "$rc" = 0 ]; then
        echo "  pre-check $(basename "$c"): 통과해버림 — 체크가 무의미(거짓 PASS)"; ok=0
      fi
    done
    [ "$ok" = 1 ] && echo "  pre-checks: 전부 만점 미만 (정상)"
  fi

  # ② solution 실행 후: 체크가 전부 PASS 여야 한다
  if [ "$ok" = 1 ] && [ -f "$MDIR/solution.sh" ]; then
    if run_in_pod "$POD" "$MDIR/solution.sh" "$BOOTSTRAP_TIMEOUT" "$MDIR"; then
      echo "  solution: OK"
    else
      echo "  solution: FAIL"; echo "$RUN_OUT" | tail -8 | sed 's/^/    /'; ok=0
    fi
  fi
  if [ "$ok" = 1 ]; then
    for c in "${CHECKS[@]}"; do
      rc=0; run_in_pod "$POD" "$c" "$CHECK_TIMEOUT" "$MDIR" || rc=$?
      if [ -n "$SCORE_M" ]; then     # 부분점수 스크립트 — 모범답안 뒤에는 만점이어야 한다
        if [ "$SCORE_E" = "$SCORE_M" ]; then
          echo "  post-check $(basename "$c"): PASS ($SCORE_E/$SCORE_M)"
        else
          echo "  post-check $(basename "$c"): FAIL ($SCORE_E/$SCORE_M)"
          echo "$RUN_OUT" | grep '✗' | sed 's/^/    /'; ok=0
        fi
      elif [ "$rc" = 0 ]; then
        echo "  post-check $(basename "$c"): PASS"
      else
        echo "  post-check $(basename "$c"): FAIL"; echo "$RUN_OUT" | tail -5 | sed 's/^/    /'; ok=0
      fi
    done
  fi

  if [ "$ok" = 1 ]; then PASSED+=("$M"); else FAILED+=("$M"); fi
  if [ "$KEEP" = 1 ]; then echo "  (KEEP=1 — 파드 $POD 보존)"; else
    kubectl delete pod "$POD" -n "$NS" --wait=false >/dev/null 2>&1
  fi
done

echo
echo "PASS(${#PASSED[@]}): ${PASSED[*]:-없음}"
echo "FAIL(${#FAILED[@]}): ${FAILED[*]:-없음}"
[ ${#FAILED[@]} -eq 0 ]
