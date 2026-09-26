# systemd 서비스와 journald

linux-02에서 nohup으로 데몬을 띄웠지만, 실무의 데몬은 전부 **systemd 유닛**입니다 — 부팅 자동 기동, 죽으면 재시작, 로그는 journald로 자동 수집. 이 모듈에서는 유닛을 직접 쓰고, 고장난 유닛을 journal로 진단·수리하고, 타이머로 cron을 대체합니다.

지금 시스템의 유닛들을 훑어봅시다.

서비스 유닛 목록 훑어보기:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — 메모리에 로드된 유닛 목록. `--type=service` 로 서비스만, `--no-pager` 로 less 없이 바로 출력.
- `| head -15` — 앞 15줄만. 열은 LOAD(파일 로드)·ACTIVE(상위 상태)·SUB(세부 상태) 순.

cron 서비스 상태 확인:

```
systemctl status cron --no-pager
```

- `systemctl status <유닛>` — 상태(`Active:`), 메인 PID, cgroup 프로세스 트리, 최근 로그 몇 줄을 한 화면에 보여 준다.

## 서비스 유닛 작성

가장 작은 서비스 유닛은 세 섹션이면 됩니다.

| 섹션 | 역할 |
|---|---|
| `[Unit]` | 설명, 의존성 (Description, After 등) |
| `[Service]` | 실행 방법 (ExecStart, Restart, User 등) |
| `[Install]` | enable 시 어디에 걸리는지 (WantedBy) |

과제: 8080 포트에서 정적 HTTP 서버를 돌리는 `hello-web.service`를 만드세요.

```
sudo tee /etc/systemd/system/hello-web.service <<'EOF'
[Unit]
Description=hello web

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
```

- `sudo tee <파일> <<'EOF'` — 히어독 본문을 root 권한의 `tee` 가 파일에 쓴다. (`sudo cat > 파일` 은 리다이렉트를 내 셸이 해서 권한 오류가 난다.)
- `/etc/systemd/system/` — 관리자가 만드는 유닛 파일 위치. 패키지 유닛(`/usr/lib/systemd/system/`)보다 우선한다.
- `ExecStart=` — 실행할 명령(절대 경로). `WantedBy=multi-user.target` — enable 하면 일반 부팅 목표에 매달린다.

유닛 파일을 만들거나 고친 뒤에는 **반드시 daemon-reload** — systemd는 파일을 직접 읽지 않고 메모리에 로드된 사본을 씁니다.

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — systemd 가 유닛 파일을 다시 읽게 한다. 서비스를 재시작하지는 않는다.

부팅 등록 + 즉시 시작:

```
sudo systemctl enable --now hello-web
```

- `enable` — `WantedBy` 대상에 심볼릭 링크를 만들어 부팅 시 자동 기동, `--now` — 동시에 지금 바로 `start` 까지.
- 유닛 이름의 `.service` 접미사는 생략할 수 있다.

서비스 상태 확인:

```
systemctl status hello-web --no-pager
```

- `Active: active (running)` 과 메인 PID(`python3`)가 보이면 정상 기동이다.

응답 확인:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — 진행률 없이 HTTP 요청을 보내고 응답 본문을 출력한다. `| head -3` 으로 첫 3줄(디렉터리 목록 HTML)만 본다.

`enable --now`는 "부팅 시 자동 기동 등록 + 지금 시작"입니다. 응답을 확인했으면 **[체크]** 하세요.

## journald로 고장 유닛 수리

`lab-report.service`라는 유닛이 배포되어 있는데 시작에 실패합니다. 직접 보세요.

서비스 시작 시도:

```
sudo systemctl start lab-report
```

- `systemctl start` — 서비스를 지금 기동한다(부팅 등록과 무관). 실패하면 `Job … failed` 메시지와 함께 확인 명령을 안내한다.

실패 상태 확인:

```
systemctl status lab-report --no-pager
```

- `Active: failed` 와 `code=exited, status=…` 줄에서 실패 원인 코드를 확인한다.

원인 조사는 **journalctl**로 합니다. `-u`로 유닛을 지정하고, `-e`(끝으로 이동)나 `--no-pager`를 곁들입니다.

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — journald 로그 조회. `-u <유닛>` 그 유닛의 로그만, `--no-pager` 로 바로 출력, `| tail -20` 최근 20줄.
- 실시간 추적은 `-f`, 이번 부팅만은 `-b`, 시간 범위는 `--since "10 min ago"`.

`status=203/EXEC`가 보일 겁니다 — systemd 종료 코드의 고전으로, **ExecStart의 실행 파일을 실행할 수 없다**(경로 오타, 실행 권한 없음, 셔뱅 문제)는 뜻입니다. 유닛이 가리키는 경로와 실제 파일을 대조해 보세요.

유닛이 가리키는 경로 확인:

```
systemctl cat lab-report
```

- `systemctl cat <유닛>` — systemd 가 실제로 쓰는 유닛 파일(드롭인 포함)의 내용과 경로를 보여 준다. `ExecStart=` 줄을 확인하자.

실제 파일 확인:

```
ls -l /opt/lab/bin/
```

- `ls -l` — 파일 이름과 권한(`x` 여부)을 함께 본다. 유닛의 경로와 글자 하나하나 비교한다.

과제: ExecStart 경로를 고치고(daemon-reload 잊지 말 것) 서비스를 기동하세요.

유닛 파일 수정:

```
sudo vim /etc/systemd/system/lab-report.service
```

- 유닛 파일은 root 소유라 `sudo` 로 연다. vim: `i` 입력, `Esc` → `:wq` 저장·종료.
- 수정 뒤 `daemon-reload` 를 빼먹으면 systemd 는 옛 경로로 계속 실패한다.

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

서비스 시작:

```
sudo systemctl start lab-report
```

로그 실시간 확인:

```
tail -f /var/log/lab/report.log   # Ctrl-C로 빠져나오기
```

- `tail -f` — 파일 끝을 계속 따라가며(follow) 새 줄이 생길 때마다 출력한다. 서비스가 실제로 일하는지 확인하는 용도.

active(running)이 되면 **[체크]** 하세요.

## Restart 정책으로 자가 복구

프로세스는 죽습니다 — OOM, 버그, 실수. systemd의 `Restart=`는 그때 자동으로 되살리는 안전망입니다.

| 값 | 재시작 조건 |
|---|---|
| `no` (기본) | 안 살림 |
| `on-failure` | 비정상 종료(코드≠0, 시그널)일 때만 |
| `always` | 정상 종료여도 무조건 |

과제: hello-web에 `Restart=on-failure`와 `RestartSec=1`을 추가하세요. 유닛 파일을 직접 고쳐도 되고, 원본을 안 건드리는 **드롭인**(`systemctl edit`은 대화식이라 여기서는 파일로) 방식도 좋습니다.

드롭인 디렉터리 생성:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<유닛>.d/` — 드롭인 디렉터리. 안의 `*.conf` 파일이 원본 유닛 위에 덮어써진다. 패키지가 원본을 업데이트해도 내 설정이 유지된다.

드롭인 파일 작성:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- `[Service]` 섹션에 추가할 키만 적는다. `Restart=on-failure` 비정상 종료 시 재시작, `RestartSec=1` 재시작 전 1초 대기.

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

서비스 재시작:

```
sudo systemctl restart hello-web
```

- `restart` — stop 후 start. 새 설정(드롭인)이 적용된 채 프로세스가 다시 뜬다.

정말 되살아나는지 실험해 봅시다. 메인 PID를 SIGKILL로 죽이고 몇 초 뒤 상태를 보세요.

메인 PID 확인:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — 유닛 속성을 `키=값` 으로 출력. `-p MainPID` 한 속성만, `--value` 로 `MainPID=` 없이 값만.

프로세스 강제 종료:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- `$( ... )` 로 얻은 메인 PID 에 `kill -9`(SIGKILL) — 가로챌 수 없는 강제 종료다. 이것은 "비정상 종료"라 `on-failure` 대상이 된다.

잠시 후 상태 확인:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- `sleep 3` 으로 재시작(RestartSec=1) 시간을 준 뒤 상태의 앞 5줄을 본다. `Main PID` 가 이전과 달라야 한다.

PID가 바뀐 채 다시 active면 성공 — **[체크]** 하세요. (체크도 같은 실험을 한 번 더 수행합니다.)

## 타이머로 주기 작업

cron의 systemd식 대체가 **타이머**입니다. 로그가 journal에 남고, 실패를 유닛으로 관리할 수 있어 요즘 배포판의 정기 작업은 대부분 타이머입니다. 구성은 **서비스(할 일) + 타이머(언제)** 한 쌍입니다.

과제: 1분마다 `/var/log/lab/tick.log`에 시각을 기록하는 `lab-tick` 타이머를 만드세요.

서비스 유닛(할 일) 작성:

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — 실행하고 끝나는 작업. 명령이 종료되면 성공으로 보고 비활성 상태로 돌아간다.
- `bash -c '…'` — 리다이렉트(`>>`, 추가 쓰기)는 셸 기능이라 bash 를 거쳐 실행한다. `date -Is` 는 ISO 8601 형식 시각.

타이머 유닛(언제) 작성:

```
sudo tee /etc/systemd/system/lab-tick.timer <<'EOF'
[Unit]
Description=lab tick every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
```

- `OnCalendar=*-*-* *:*:00` — `연-월-일 시:분:초` 달력식. 매일 매시 매분 0초 = 1분마다.
- `AccuracySec=1s` — 실행 시각 오차 허용치(기본 1분)를 1초로 줄인다.
- 타이머는 같은 이름의 `.service`(여기선 `lab-tick.service`)를 실행한다. `WantedBy=timers.target` 으로 enable 된다.

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

타이머 등록·시작:

```
sudo systemctl enable --now lab-tick.timer
```

- `.timer` 까지 이름을 정확히 써야 한다. 생략하면 `.service` 로 해석된다.

`Type=oneshot`은 "한 번 실행하고 끝나는" 작업용입니다. enable 대상이 **service가 아니라 timer**라는 점에 주의하세요. 등록 상태를 확인하고 **[체크]** 하면 모듈 완료입니다.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — 활성 타이머의 다음(`NEXT`)·마지막(`LAST`) 실행 시각.
- `grep -E 'NEXT|lab-tick'` — 헤더 줄과 lab-tick 줄만 남긴다(`|` 는 확장 정규식의 OR).
