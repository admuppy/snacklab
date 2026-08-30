# Bash 스크립팅

한 줄짜리 명령이 반복되기 시작하면 스크립트로 만들 때입니다. 이 모듈에서는 **죽지 않는 스크립트가 아니라, 문제가 생기면 바로 죽는(fail-fast) 스크립트**를 짜는 법을 배웁니다 — 조용히 잘못된 결과를 내는 스크립트가 가장 위험하기 때문입니다.

작성 위치는 모두 `~/work/` 아래입니다. 에디터는 vim/nano 어느 쪽이든 좋고, `cat > 파일 <<'EOF'` 히어독으로 만들어도 됩니다.

## 안전한 스크립트 골격

모든 스크립트의 첫 두 줄은 사실상 고정입니다.

```
#!/bin/bash
set -euo pipefail
```

| 옵션 | 효과 |
|---|---|
| `-e` | 명령이 실패하면 즉시 종료 |
| `-u` | 정의 안 된 변수 참조 시 에러 (오타 방지) |
| `-o pipefail` | 파이프 중간 단계 실패도 실패로 처리 |

과제: `~/work/sysinfo.sh` 를 작성하세요. 요구사항:

- bash 셔뱅 + `set -euo pipefail`
- `host=<호스트명>` 한 줄, `uptime=<초>` 한 줄 출력
- 실행 권한

스크립트 작성:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

실행 권한 부여:

```
chmod +x ~/work/sysinfo.sh
```

실행해 보기:

```
~/work/sysinfo.sh
```

동작을 확인하고 **[체크]** 하세요.

## 인자 처리와 종료 코드

스크립트의 인자는 `$1 $2 …`, 개수는 `$#`로 받습니다. 잘못 호출되면 **usage를 stderr로 출력하고 0이 아닌 코드로 종료**하는 것이 규약입니다 — 호출한 쪽(다른 스크립트, CI)이 실패를 감지할 수 있어야 하니까요.

과제: `~/work/logcut.sh <로그파일> <상태코드>` 를 작성하세요.

- `/opt/lab/data/app.log` 형식(`… status=200 msg=…`)에서 해당 상태코드 라인 수를 출력
- 인자가 2개가 아니면 usage 출력 + 종료 코드 2

스크립트 작성:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

실행 권한 부여:

```
chmod +x ~/work/logcut.sh
```

> `grep -c`는 매칭이 0건이면 **종료 코드 1**을 냅니다. `set -e` 아래에서는 그대로 죽으므로 `|| true`로 "0건도 정상"임을 명시합니다 — fail-fast는 켜되, 실패가 아닌 것은 실패로 취급하지 않는 감각이 중요합니다.

테스트해 보고 **[체크]** 하세요.

정상 호출 — 500 라인 수 출력:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

인자 없이 호출 — 종료 코드 2 확인:

```
~/work/logcut.sh; echo "exit=$?"
```

## trap으로 정리 보장

임시 파일을 만드는 스크립트가 중간에 죽으면 쓰레기가 남습니다. `trap '…' EXIT`는 **정상 종료든 에러든** 스크립트가 끝날 때 항상 실행되는 정리 훅입니다.

과제: `~/work/withtmp.sh` 를 작성하세요.

- `mktemp -d`로 임시 디렉터리 생성, 그 안에 아무 파일이나 하나 생성
- `trap`으로 종료 시 임시 디렉터리 삭제
- **마지막 출력 줄**로 임시 디렉터리 경로를 출력 (검증이 이 경로가 지워졌는지 확인합니다)

스크립트 작성:

```
cat > ~/work/withtmp.sh <<'EOF'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
date > "$tmp/scratch.txt"
echo "$tmp"
EOF
```

실행 권한 부여:

```
chmod +x ~/work/withtmp.sh
```

실행 후 삭제 확인:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" 이어야 정상
```

확인했으면 **[체크]** 하세요.

## 고장난 스크립트 수리

마지막은 현실에서 가장 자주 하는 일 — **남이 짠 스크립트 고치기**입니다. `/opt/lab/bin/backup.sh` 는 디렉터리를 /tmp로 백업하는 스크립트인데, 경로에 **공백이 들어가면** 죽습니다.

스크립트 내용 보기:

```
cat /opt/lab/bin/backup.sh
```

공백 경로 테스트 디렉터리 준비:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

공백 경로로 실행:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # 실패!
```

원인은 **인용(quoting) 없는 변수 확장**입니다. `$src`가 `/tmp/my app`이면 `cp -r $src/*`는 `/tmp/my`와 `app/*` 두 인자로 쪼개집니다. 쉘 스크립트 버그의 고전 중의 고전입니다.

과제: `~/work/backup-fixed.sh` 로 복사한 뒤 고치세요.

- 모든 변수 확장을 `"…"`로 인용 (`"$dest"`, `"$src"/*` — 글롭 `*`는 인용 밖에!)
- `set -euo pipefail` 추가
- 공백 경로로 실행해서 성공 확인

사본 만들기:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

에디터로 고치기:

```
vim ~/work/backup-fixed.sh
```

공백 경로로 실행해 확인:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

성공하면 **[체크]** — 모듈 완료입니다.
