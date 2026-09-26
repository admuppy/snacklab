# CPU·메모리 관리

서버가 느려졌다는 신고가 들어오면 가장 먼저 보는 것이 **CPU와 메모리**입니다. 이 모듈에서는 자원을 관찰하는 도구부터, 프로세스 우선순위 조정, 그리고 컨테이너/파드의 실질적 상한인 **cgroup 메모리 제한과 OOM**까지 다룹니다.

> 이 실습 환경은 systemd가 도는 **컨테이너(파드)**입니다. 자원 제한도 실제 k8s 파드와 같은 방식(systemd가 관리하는 cgroup v2)으로 다룹니다 — 물리 서버와 다른 부분은 그때그때 짚어줍니다.

먼저 현재 상태를 훑어봅니다.

CPU 수 확인:

```
nproc
```

- `nproc` — 현재 프로세스가 쓸 수 있는 CPU(코어) 수. 컨테이너에선 cgroup·친화도 제한이 반영된 값이다.

메모리 현황 확인:

```
free -h
```

- `free` — 메모리·스왑 사용량. `-h` 로 Gi/Mi 단위.
- `available` 열이 "새 프로세스가 실제로 쓸 수 있는 양"(캐시 회수분 포함)이라 `free` 열보다 중요하다.

1초 간격 요약 3회:

```
vmstat 1 3
```

- `vmstat <간격> <횟수>` — 1초 간격으로 3번 출력. 첫 줄은 부팅 후 평균이라 두 번째 줄부터 본다.
- `r` 실행 대기 프로세스, `si/so` 스왑 in/out, `us/sy/id/wa` CPU 사용자/커널/유휴/IO대기 비율.

top 스냅샷 한 장:

```
top -b -n1 | head -12
```

- `top -b` — 대화형 화면 대신 텍스트로 출력(batch), `-n1` — 한 번만. `| head -12` 로 요약 영역과 상위 프로세스 몇 개만.

## 자원 관찰

`free`는 메모리를, `vmstat`는 메모리·스왑·CPU를 한 줄로 요약합니다. 원본 수치는 `/proc/meminfo`와 `/proc/cpuinfo`에 있습니다.

| 명령 | 무엇을 보나 |
|---|---|
| `free -h` | 전체/사용/가용 메모리, swap |
| `vmstat 1` | 1초 간격 메모리·swap in/out(si/so)·CPU |
| `nproc` | 이 환경에서 쓸 수 있는 CPU 수 |
| `cat /proc/meminfo` | MemTotal·MemAvailable 등 원본 |

과제: 현재 메모리 총량과 CPU 수를 스냅샷으로 남깁니다. `~/work/snapshot.txt`에 **/proc/meminfo의 MemTotal 줄**과 **`cpus=<nproc 값>`** 줄을 저장하세요.

작업 디렉터리 준비:

```
mkdir -p ~/work
```

- `mkdir -p` — 상위 디렉터리까지 만들고, 이미 있어도 에러를 내지 않는다.

MemTotal 줄 저장:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — 전체 메모리 줄만 골라 `>` 로 파일에 저장(새로 쓰기)한다.

cpus 줄 추가:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — 큰따옴표 안에서도 `$( )` 가 치환되어 `cpus=4` 같은 문자열이 된다.
- `>>` — 파일 끝에 **추가**한다(`>` 는 덮어쓰기).

저장된 내용 확인:

```
cat ~/work/snapshot.txt
```

- 두 줄(MemTotal, cpus=…)이 들어 있는지 확인한다.

기록했으면 **[체크]** 하세요.

## 우선순위와 CPU 친화도

CPU가 부족할 때 모든 프로세스를 똑같이 대접할 수는 없습니다. **nice 값**(-20 높음 ~ 19 낮음)으로 스케줄러 우선순위를, **taskset**으로 어느 코어에서 돌지(CPU 친화도)를 정합니다.

| 명령 | 역할 |
|---|---|
| `nice -n 19 CMD` | 낮은 우선순위로 새 프로세스 시작 |
| `renice -n 5 -p PID` | 실행 중 프로세스의 nice 변경 |
| `taskset -c 0 CMD` | CPU 0번에만 고정해서 실행 |
| `taskset -pc PID` | 실행 중 프로세스의 친화도 조회/변경 |

과제: CPU를 태우는 부하(`stress-ng --cpu 1`)를 **CPU 0번에 고정**하고 **nice 19**(가장 양보하는 우선순위)로 백그라운드 실행하세요. 배치 작업을 남의 서비스에 방해되지 않게 돌리는 전형적 패턴입니다.

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <명령>` — 명령을 CPU 0번에만 고정해 실행한다(`-c` 는 CPU 번호 목록, 예: `0,2` 또는 `0-3`).
- `nice -n 19 <명령>` — nice 값 19(가장 낮은 우선순위)로 실행. 두 래퍼를 겹쳐 쓸 수 있다.
- `stress-ng --cpu 1 --timeout 1800s` — CPU 하나를 30분간 100% 로 태우는 부하 생성기.
- `>/dev/null 2>&1 &` — 출력은 버리고 백그라운드로 실행한다.

정말 그렇게 떴는지 확인합니다. `top`에서 `NI` 열이 19인지, 친화도가 CPU 0인지 보세요.

부하 프로세스 PID 저장:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — 전체 커맨드라인에서 정규식으로 찾는다(`.*` 는 아무 문자 여러 개). `head -1` 로 첫 PID 만 `pid` 에 저장.

nice 값 확인:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — PID·nice 값(`NI`)·명령 이름 열만. `-p "$pid"` 로 그 프로세스 하나만.

CPU 친화도 확인:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — 실행 중 프로세스의 친화도를 조회한다. `-c` 를 더하면 비트마스크 대신 CPU 번호 목록으로 보여 준다.

/proc 에서 교차 확인:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `/proc/<PID>/status` 의 `Cpus_allowed_list` — 커널이 기록한 "이 프로세스가 돌 수 있는 CPU" 목록. taskset 결과와 같아야 한다.

`NI=19`, 친화도 `0`이면 **[체크]** 하세요. (부하 프로세스는 계속 돌게 둡니다 — 다음 단계에 영향 없습니다.)

## cgroup 메모리 제한과 OOM

리눅스에서 프로세스 그룹의 CPU·메모리 상한은 **cgroup v2**가 강제합니다. 컨테이너 자원 제한, systemd 서비스의 `MemoryMax=`, 그리고 **k8s 파드의 `resources.limits.memory`가 전부 이 위에서** 돕니다. 여기서는 **메모리 상한을 건 cgroup을 만들어** 메모리를 초과시키고, 커널의 **OOM Killer**가 동작하는 것을 눈으로 봅니다.

먼저 cgroup 트리와 제어기(controller)를 봅니다.

파일시스템 타입 확인:

```
stat -fc %T /sys/fs/cgroup        # cgroup2fs 여야 함
```

- `stat -f` — 파일이 아니라 그 파일이 있는 **파일시스템** 정보를, `-c %T` — 형식 지정으로 타입 이름만 출력한다. `cgroup2fs` 면 cgroup v2.

사용 가능한 제어기 확인:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- 이 cgroup 에서 쓸 수 있는 제어기 목록(`cpu`, `memory`, `io`, `pids` …). `memory` 가 있어야 메모리 상한을 걸 수 있다.

> 💡 이 파드는 **호스트 cgroup 네임스페이스**를 공유합니다. 즉 `/sys/fs/cgroup`은 노드 전체의 트리입니다. 여기에 손으로 `mkdir` 하면 **노드를 오염**시키고 다른 파드와 충돌합니다. 그래서 상한 cgroup은 systemd에게 맡겨 **파드 자신의 슬라이스 안에** 만듭니다 — k8s가 파드마다 cgroup을 만들어 주는 것과 똑같은 방식입니다.

과제: `lab.slice`라는 슬라이스에 **메모리 24M·스왑 0** 상한을 걸고, 그 안에서 200MB를 할당하는 프로세스를 돌려 OOM을 유도하세요.

```
# 슬라이스에 메모리 상한 부여 (--runtime = 재부팅까지만, 디스크에 남기지 않음)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <유닛> 키=값…` — 실행 중 유닛(여기선 슬라이스)의 자원 속성을 바꾼다.
- `MemoryMax=24M` — cgroup `memory.max`(하드 상한), `MemorySwapMax=0` — 스왑으로 도망가지 못하게 막는다.
- `--runtime` — 재부팅하면 사라지는 임시 설정(`/run` 에 저장).

이제 그 슬라이스 안에서 메모리를 초과 할당합니다. `systemd-run --slice=lab.slice --scope`는 지정한 슬라이스 밑에 임시 스코프를 만들어 명령을 실행합니다.

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — 명령을 현재 터미널에서 그대로 실행하되 새 임시 스코프(cgroup)에 넣는다. `--slice=lab.slice` 로 상한이 걸린 슬라이스 아래에.
- `python3 -c "…"` — 4MB 바이트 배열을 200개(≈800MB) 만드는 한 줄 프로그램. 줄 끝 `\` 는 다음 줄로 이어짐.

`Killed`가 뜰 겁니다 — 24M 상한을 넘자 커널이 프로세스를 죽인 것입니다. 흔적은 슬라이스 cgroup의 `memory.events`에 남습니다. 슬라이스의 실제 cgroup 경로는 systemd가 알려줍니다.

슬라이스의 cgroup 경로 저장:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — 슬라이스의 cgroup 경로(`/…/lab.slice`)를 출력한다. 앞에 `/sys/fs/cgroup` 을 붙여 실제 디렉터리 경로를 변수 `cg` 에 담는다.

메모리 상한 확인:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — 이 cgroup 의 메모리 하드 상한(바이트). 24M = 24×1024×1024 = 25165824.

OOM 이벤트 확인:

```
cat "$cg/memory.events"     # oom_kill 항목 확인
```

- `memory.events` — 이 cgroup 에서 일어난 메모리 이벤트 누적 횟수. `max` 상한 도달, `oom` OOM 발생, `oom_kill` OOM 으로 죽은 프로세스 수.

`oom_kill 1`(또는 그 이상)이 보이면 OOM이 실제로 일어난 것입니다. 확인했으면 **[체크]** 하면 모듈 완료입니다. (`lab.slice`는 파드가 살아있는 동안 유지되며, 파드가 사라지면 자동으로 정리됩니다.)
