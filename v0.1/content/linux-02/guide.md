# 프로세스와 시그널

서버가 느리거나 이상할 때 제일 먼저 하는 일은 **프로세스를 들여다보는 것**입니다. 이 모듈에서는 ps와 /proc으로 프로세스를 탐색하고, 시그널로 제어하고, 터미널과 분리된 백그라운드 실행을 만들고, 포트를 점유한 프로세스를 추적합니다.

실습 환경에는 세 개의 데몬이 systemd 유닛으로 미리 떠 있습니다.

| 프로세스 | 정체 |
|---|---|
| `lab-worker` | 평범한 워커 — 1단계 탐색 대상 |
| `lab-stubborn` | **SIGTERM을 무시**하는 좀비 같은 녀석 — 2단계에서 처치 |
| `lab-listener` | 127.0.0.1:5555 를 점유한 무언가 — 4단계에서 추적 |

## 프로세스 탐색 — ps와 /proc

먼저 전체 프로세스를 훑어봅니다.

전체 목록 훑어보기:

```
ps aux | head
```

- `ps aux` — 모든 사용자(`a`, `x`: 터미널 없는 것 포함)의 프로세스를 사용자·CPU%·MEM%·명령과 함께(`u`) 보여 준다.
- `| head` — 앞 10줄만 본다.

트리 형태로 보기:

```
ps -ef --forest | head -30
```

- `ps -ef` — 모든 프로세스(`-e`)를 PID·PPID 가 포함된 전체 형식(`-f`)으로.
- `--forest` — 부모-자식 관계를 들여쓰기 트리로 그린다. `head -30` 으로 앞 30줄만.

`lab-worker`를 찾아봅시다. `pgrep -f`는 커맨드라인 전체에서 패턴을 찾아 PID를 돌려줍니다.

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <패턴>` — 이름이 패턴에 맞는 프로세스의 PID 만 출력한다.
- `-f` — 프로세스 이름이 아니라 **전체 커맨드라인**(경로·인자 포함)에서 찾는다.

ps가 보여 주는 모든 정보의 원천은 **/proc 파일시스템**입니다. PID 디렉터리 안을 직접 확인해 보세요 (cmdline은 NUL(\0)로 구분되어 있어 tr로 바꿔 읽습니다).

PID를 변수에 저장:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — 명령 치환. 출력(PID)을 셸 변수 `pid` 에 담는다. 이후 `$pid` 로 쓴다.
- `| head -1` — 여러 개가 걸려도 첫 번째 PID 하나만.

PID 디렉터리 내용 확인:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — 커널이 프로세스 정보를 파일처럼 보여 주는 가상 디렉터리. `cmdline`(실행 인자), `status`(상태·메모리), `fd/`(열린 파일), `environ`(환경변수) 등이 있다.

cmdline 읽기:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — 입력의 NUL 문자를 공백으로 바꾼다(translate).
- `< 파일` — 파일을 표준입력으로 넣는다. `; echo` 는 마지막에 줄바꿈을 더한다.

과제: 결과를 파일로 저장하세요.

- `~/work/worker.pid` — lab-worker의 PID
- `~/work/worker.cmdline` — `/proc/<PID>/cmdline` 내용 (tr 변환본)

작업 디렉터리 생성:

```
mkdir -p ~/work
```

- `mkdir -p` — 필요한 상위 디렉터리까지 만들고, 이미 있어도 에러를 내지 않는다.

PID 저장:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` — 변수 값을 출력. `> 파일` 로 그 출력을 파일에 저장(덮어쓰기)한다.

cmdline 저장:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- 앞서 화면에 출력했던 `tr` 명령과 같다. 이번엔 결과를 `>` 로 파일에 저장한다.

저장했으면 **[체크]** 하세요.

## 시그널로 프로세스 제어

`kill`은 프로세스를 죽이는 명령이 아니라 **시그널을 보내는** 명령입니다.

| 시그널 | 번호 | 특징 |
|---|---|---|
| SIGTERM | 15 | 기본값. 프로세스가 **무시하거나 정리 후 종료 가능** |
| SIGKILL | 9 | 커널이 즉시 제거. **무시 불가**, 정리 기회 없음 |
| SIGHUP | 1 | 관례상 "설정 리로드"로 많이 쓰임 |

`lab-stubborn`은 TERM과 INT를 trap으로 무시하도록 짜여 있습니다. 직접 확인해 보세요.

살아 있는지 확인:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- PID 가 출력되면 살아 있는 것이다. 아무것도 안 나오면(종료코드 1) 해당 프로세스가 없다.

SIGTERM 보내기:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — 패턴에 맞는 프로세스에 시그널을 보낸다(`pgrep` + `kill`).
- `-TERM` — 보낼 시그널(SIGTERM, 15). `-f` 로 전체 커맨드라인에서 찾는다.
- `sudo` — 다른 사용자(root)가 띄운 프로세스라 관리자 권한이 필요하다.

여전히 살아 있는지 확인:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # 여전히 살아 있음
```

- `sleep 1` — 1초 기다린다. 시그널 처리 시간을 준 뒤 `;` 로 이어서 다시 확인한다.

주의할 점: 이 프로세스는 **systemd 유닛**(lab-stubborn.service)이 관리합니다. 프로세스만 kill -9 해도 되지만, 유닛으로 관리되는 프로세스는 유닛 차원에서 다루는 게 정석입니다. 다만 `systemctl stop`은 먼저 TERM을 보내고 타임아웃(기본 90초)까지 기다리므로 이 녀석에겐 느립니다 — **유닛을 통해 SIGKILL을 바로 보내는** 방법을 쓰세요.

유닛을 통해 SIGKILL 보내기:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <유닛>` — 유닛에 속한 **모든 프로세스**에 시그널을 보낸다.
- `-s KILL` — 보낼 시그널을 SIGKILL(9)로. 프로세스가 가로챌 수 없어 즉시 제거된다.

종료 확인:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "종료됨"
```

- `A || B` — A 가 실패(종료코드 ≠ 0)했을 때만 B 를 실행한다. `pgrep` 이 아무것도 못 찾으면 메시지가 나온다.

죽었으면 **[체크]** 하세요.

## 세션과 분리된 백그라운드 실행

터미널에서 `&`로 띄운 프로세스는 터미널이 끊기면 SIGHUP을 받고 함께 죽습니다. 세션이 끝나도 살아남게 하려면 **nohup**(HUP 무시 + 출력 리다이렉트)이나 **setsid**(새 세션 분리)를 씁니다.

`/opt/lab/bin/lab-batch`는 첫 인자로 받은 파일에 10초마다 timestamp를 쓰는 배치입니다. 이걸 터미널과 분리해서 띄우고, 로그는 `~/work/batch.log`로 보내세요.

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <명령>` — SIGHUP 을 무시하게 해서 터미널이 닫혀도 계속 돈다.
- `>/dev/null 2>&1` — 표준출력을 버리고, 표준에러(2)도 표준출력(1)과 같은 곳으로 보낸다.
- 끝의 `&` — 백그라운드로 실행하고 프롬프트를 바로 돌려준다.

부모 프로세스를 확인해 보세요. 셸에서 분리되어 고아가 되면 PID 1(pod에서는 systemd)이 거둬 갑니다.

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — 출력할 열을 PID·부모 PID·명령으로 지정한다.
- `-p $(pgrep ...)` — 명령 치환으로 얻은 PID 의 프로세스만 조회한다.

로그 확인:

```
tail ~/work/batch.log
```

- `tail <파일>` — 파일 끝 10줄. 계속 따라가며 보려면 `tail -f` (Ctrl+C 로 종료).

PPID가 1이고 로그가 쌓이고 있으면 **[체크]** 하세요.

> 실무에서는 이런 임시 데몬보다 systemd 유닛(또는 `systemd-run`)이 정답입니다 — linux-06 모듈에서 다룹니다.

## 포트 점유 프로세스 추적

"이 포트 누가 잡고 있어?"는 가장 흔한 진단 질문입니다. `ss`(socket statistics)로 5555 포트의 주인을 찾아보세요. 프로세스 이름을 보려면 `-p`가 필요하고, 남의 프로세스는 sudo가 있어야 보입니다.

리스닝 소켓 전체 보기:

```
sudo ss -ltnp
```

- `ss` — 소켓 상태 조회(netstat 후속). `-l` 리스닝 소켓만, `-t` TCP, `-n` 포트를 이름 대신 숫자로, `-p` 소켓을 연 프로세스까지 표시.

5555 포트만 조회:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — 필터식. 소스(로컬) 포트가 5555 인 소켓만 보여 준다.

`lsof`로도 같은 답을 얻을 수 있습니다.

```
sudo lsof -i :5555
```

- `lsof` — 열린 파일 목록(리눅스에선 소켓도 파일). `-i :5555` — 5555 포트를 쓰는 네트워크 연결만.

과제: 5555 포트를 점유한 **프로세스 이름**을 `~/work/port-owner.txt`에 저장하세요.

프로세스 이름 추출·저장:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — 줄 전체가 아니라 **매칭된 부분만** 출력한다. `users:(("python3",pid=…))` 에서 이름만 뽑는다.
- `head -1` 로 하나만 남겨 `>` 로 저장.

저장 내용 확인:

```
cat ~/work/port-owner.txt
```

- `cat <파일>` — 파일 내용을 그대로 출력한다.

이 python3의 정체가 궁금하면 PID로 /proc을 다시 뒤져 보세요 — 1단계에서 배운 방법 그대로입니다. 저장했으면 **[체크]** 하세요.
