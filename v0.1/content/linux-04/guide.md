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

- `cat > 파일 <<'EOF'` … `EOF` — 히어독. 두 `EOF` 사이의 줄들을 `cat` 의 입력으로 넣고, `>` 로 파일에 저장한다. `'EOF'` 처럼 따옴표를 치면 본문의 `$(...)` 가 지금 실행되지 않고 글자 그대로 저장된다.
- `#!/bin/bash` — 셔뱅. 이 파일을 어떤 인터프리터로 실행할지 커널에 알린다.
- `$(uname -n)` — 호스트명, `awk '{print $1}' /proc/uptime` — 부팅 후 경과 초(첫 필드).

실행 권한 부여:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — 실행(x) 권한을 추가한다. 없으면 `./스크립트` 로 실행할 때 `Permission denied`.

실행해 보기:

```
~/work/sysinfo.sh
```

- 경로로 직접 실행하면 셔뱅의 `/bin/bash` 가 스크립트를 실행한다. (`bash 파일` 로 실행하면 실행 권한이 없어도 된다.)

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

- `usage() { …; }` — 함수 정의. `>&2` 는 메시지를 표준에러로, `exit 2` 는 종료 코드 2 로 끝낸다.
- `[ $# -eq 2 ] || usage` — 인자 개수(`$#`)가 2 가 아니면(`||`) usage 호출. `[ ]` 는 조건 검사 명령(`test`).
- `grep -c "status=$2 " "$1"` — 두 번째 인자 상태 코드의 줄 수. 변수는 큰따옴표로 감싸 공백이 든 경로도 안전하게.

실행 권한 부여:

```
chmod +x ~/work/logcut.sh
```

- 새 스크립트마다 실행 권한을 줘야 한다.

> `grep -c`는 매칭이 0건이면 **종료 코드 1**을 냅니다. `set -e` 아래에서는 그대로 죽으므로 `|| true`로 "0건도 정상"임을 명시합니다 — fail-fast는 켜되, 실패가 아닌 것은 실패로 취급하지 않는 감각이 중요합니다.

테스트해 보고 **[체크]** 하세요.

정상 호출 — 500 라인 수 출력:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- 첫 인자가 `$1`(로그 파일), 두 번째가 `$2`(상태 코드)로 들어간다.

인자 없이 호출 — 종료 코드 2 확인:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — 바로 앞 명령의 종료 코드. `;` 로 이어서 usage 뒤 코드가 2 인지 확인한다.

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

- `mktemp -d` — 겹치지 않는 이름의 임시 디렉터리를 만들고 그 경로를 출력한다.
- `trap '명령' EXIT` — 스크립트가 어떤 이유로 끝나든 종료 직전에 명령을 실행한다. 여기선 임시 디렉터리 삭제.
- `rm -rf "$tmp"` — 디렉터리를 내용째(`-r`) 묻지 않고(`-f`) 지운다. trap 본문은 작은따옴표라 `$tmp` 가 실행 시점에 풀린다.

실행 권한 부여:

```
chmod +x ~/work/withtmp.sh
```

- 실행 권한 부여.

실행 후 삭제 확인:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" 이어야 정상
```

- `d=$(스크립트)` — 스크립트 출력(임시 경로)을 변수 `d` 에 담는다.
- `ls -d "$d"` — 디렉터리 자체를 조회. `2>&1` 로 에러 메시지도 화면에 보이게 한다. 이미 지워졌으니 `No such file` 이 정상.

확인했으면 **[체크]** 하세요.

## 고장난 스크립트 수리

마지막은 현실에서 가장 자주 하는 일 — **남이 짠 스크립트 고치기**입니다. `/opt/lab/bin/backup.sh` 는 디렉터리를 /tmp로 백업하는 스크립트인데, 경로에 **공백이 들어가면** 죽습니다.

스크립트 내용 보기:

```
cat /opt/lab/bin/backup.sh
```

- 고치기 전에 먼저 읽는다. 따옴표 없이 쓰인 `$src`, `$dest` 를 찾아보자.

공백 경로 테스트 디렉터리 준비:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- 경로에 공백이 있으므로 큰따옴표로 감싸 한 인자로 넘긴다. `;` 로 이어 테스트 파일도 하나 만든다.

공백 경로로 실행:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # 실패!
```

- 호출할 때는 따옴표로 한 인자를 넘겼지만, 스크립트 안에서 따옴표 없이 `$src` 를 쓰는 순간 다시 두 단어로 쪼개진다(word splitting).

원인은 **인용(quoting) 없는 변수 확장**입니다. `$src`가 `/tmp/my app`이면 `cp -r $src/*`는 `/tmp/my`와 `app/*` 두 인자로 쪼개집니다. 쉘 스크립트 버그의 고전 중의 고전입니다.

과제: `~/work/backup-fixed.sh` 로 복사한 뒤 고치세요.

- 모든 변수 확장을 `"…"`로 인용 (`"$dest"`, `"$src"/*` — 글롭 `*`는 인용 밖에!)
- `set -euo pipefail` 추가
- 공백 경로로 실행해서 성공 확인

사본 만들기:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <원본> <대상>` — 원본은 그대로 두고 내 작업 디렉터리에 사본을 만든다.

에디터로 고치기:

```
vim ~/work/backup-fixed.sh
```

- vim: `i` 로 입력 모드, 고친 뒤 `Esc` → `:wq` 로 저장·종료. 익숙하지 않으면 `nano` 를 써도 된다(`Ctrl+O` 저장, `Ctrl+X` 종료).

공백 경로로 실행해 확인:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — A 가 성공(종료 코드 0)했을 때만 B 를 실행한다. `OK` 가 보이면 수리 성공.

성공하면 **[체크]** — 모듈 완료입니다.
