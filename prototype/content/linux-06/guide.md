# systemd 서비스와 journald

linux-02에서 nohup으로 데몬을 띄웠지만, 실무의 데몬은 전부 **systemd 유닛**입니다 — 부팅 자동 기동, 죽으면 재시작, 로그는 journald로 자동 수집. 이 모듈에서는 유닛을 직접 쓰고, 고장난 유닛을 journal로 진단·수리하고, 타이머로 cron을 대체합니다.

지금 시스템의 유닛들을 훑어봅시다.

서비스 유닛 목록 훑어보기:

```
systemctl list-units --type=service --no-pager | head -15
```

cron 서비스 상태 확인:

```
systemctl status cron --no-pager
```

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

유닛 파일을 만들거나 고친 뒤에는 **반드시 daemon-reload** — systemd는 파일을 직접 읽지 않고 메모리에 로드된 사본을 씁니다.

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

부팅 등록 + 즉시 시작:

```
sudo systemctl enable --now hello-web
```

서비스 상태 확인:

```
systemctl status hello-web --no-pager
```

응답 확인:

```
curl -s http://127.0.0.1:8080/ | head -3
```

`enable --now`는 "부팅 시 자동 기동 등록 + 지금 시작"입니다. 응답을 확인했으면 **[체크]** 하세요.

## journald로 고장 유닛 수리

`lab-report.service`라는 유닛이 배포되어 있는데 시작에 실패합니다. 직접 보세요.

서비스 시작 시도:

```
sudo systemctl start lab-report
```

실패 상태 확인:

```
systemctl status lab-report --no-pager
```

원인 조사는 **journalctl**로 합니다. `-u`로 유닛을 지정하고, `-e`(끝으로 이동)나 `--no-pager`를 곁들입니다.

```
journalctl -u lab-report --no-pager | tail -20
```

`status=203/EXEC`가 보일 겁니다 — systemd 종료 코드의 고전으로, **ExecStart의 실행 파일을 실행할 수 없다**(경로 오타, 실행 권한 없음, 셔뱅 문제)는 뜻입니다. 유닛이 가리키는 경로와 실제 파일을 대조해 보세요.

유닛이 가리키는 경로 확인:

```
systemctl cat lab-report
```

실제 파일 확인:

```
ls -l /opt/lab/bin/
```

과제: ExecStart 경로를 고치고(daemon-reload 잊지 말 것) 서비스를 기동하세요.

유닛 파일 수정:

```
sudo vim /etc/systemd/system/lab-report.service
```

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

드롭인 파일 작성:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

서비스 재시작:

```
sudo systemctl restart hello-web
```

정말 되살아나는지 실험해 봅시다. 메인 PID를 SIGKILL로 죽이고 몇 초 뒤 상태를 보세요.

메인 PID 확인:

```
systemctl show -p MainPID --value hello-web
```

프로세스 강제 종료:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

잠시 후 상태 확인:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

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

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

타이머 등록·시작:

```
sudo systemctl enable --now lab-tick.timer
```

`Type=oneshot`은 "한 번 실행하고 끝나는" 작업용입니다. enable 대상이 **service가 아니라 timer**라는 점에 주의하세요. 등록 상태를 확인하고 **[체크]** 하면 모듈 완료입니다.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```
