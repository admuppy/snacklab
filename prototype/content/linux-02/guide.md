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

트리 형태로 보기:

```
ps -ef --forest | head -30
```

`lab-worker`를 찾아봅시다. `pgrep -f`는 커맨드라인 전체에서 패턴을 찾아 PID를 돌려줍니다.

```
pgrep -f /opt/lab/bin/lab-worker
```

ps가 보여 주는 모든 정보의 원천은 **/proc 파일시스템**입니다. PID 디렉터리 안을 직접 확인해 보세요 (cmdline은 NUL(\0)로 구분되어 있어 tr로 바꿔 읽습니다).

PID를 변수에 저장:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

PID 디렉터리 내용 확인:

```
ls /proc/$pid/
```

cmdline 읽기:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

과제: 결과를 파일로 저장하세요.

- `~/work/worker.pid` — lab-worker의 PID
- `~/work/worker.cmdline` — `/proc/<PID>/cmdline` 내용 (tr 변환본)

작업 디렉터리 생성:

```
mkdir -p ~/work
```

PID 저장:

```
echo "$pid" > ~/work/worker.pid
```

cmdline 저장:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

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

SIGTERM 보내기:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

여전히 살아 있는지 확인:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # 여전히 살아 있음
```

주의할 점: 이 프로세스는 **systemd 유닛**(lab-stubborn.service)이 관리합니다. 프로세스만 kill -9 해도 되지만, 유닛으로 관리되는 프로세스는 유닛 차원에서 다루는 게 정석입니다. 다만 `systemctl stop`은 먼저 TERM을 보내고 타임아웃(기본 90초)까지 기다리므로 이 녀석에겐 느립니다 — **유닛을 통해 SIGKILL을 바로 보내는** 방법을 쓰세요.

유닛을 통해 SIGKILL 보내기:

```
sudo systemctl kill -s KILL lab-stubborn
```

종료 확인:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "종료됨"
```

죽었으면 **[체크]** 하세요.

## 세션과 분리된 백그라운드 실행

터미널에서 `&`로 띄운 프로세스는 터미널이 끊기면 SIGHUP을 받고 함께 죽습니다. 세션이 끝나도 살아남게 하려면 **nohup**(HUP 무시 + 출력 리다이렉트)이나 **setsid**(새 세션 분리)를 씁니다.

`/opt/lab/bin/lab-batch`는 첫 인자로 받은 파일에 10초마다 timestamp를 쓰는 배치입니다. 이걸 터미널과 분리해서 띄우고, 로그는 `~/work/batch.log`로 보내세요.

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

부모 프로세스를 확인해 보세요. 셸에서 분리되어 고아가 되면 PID 1(pod에서는 systemd)이 거둬 갑니다.

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

로그 확인:

```
tail ~/work/batch.log
```

PPID가 1이고 로그가 쌓이고 있으면 **[체크]** 하세요.

> 실무에서는 이런 임시 데몬보다 systemd 유닛(또는 `systemd-run`)이 정답입니다 — linux-06 모듈에서 다룹니다.

## 포트 점유 프로세스 추적

"이 포트 누가 잡고 있어?"는 가장 흔한 진단 질문입니다. `ss`(socket statistics)로 5555 포트의 주인을 찾아보세요. 프로세스 이름을 보려면 `-p`가 필요하고, 남의 프로세스는 sudo가 있어야 보입니다.

리스닝 소켓 전체 보기:

```
sudo ss -ltnp
```

5555 포트만 조회:

```
sudo ss -ltnp sport = :5555
```

`lsof`로도 같은 답을 얻을 수 있습니다.

```
sudo lsof -i :5555
```

과제: 5555 포트를 점유한 **프로세스 이름**을 `~/work/port-owner.txt`에 저장하세요.

프로세스 이름 추출·저장:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

저장 내용 확인:

```
cat ~/work/port-owner.txt
```

이 python3의 정체가 궁금하면 PID로 /proc을 다시 뒤져 보세요 — 1단계에서 배운 방법 그대로입니다. 저장했으면 **[체크]** 하세요.
