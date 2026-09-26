# 종합 — 죽은 서비스 살리기

새벽 2시, 알림이 울립니다: **"lab-app이 안 떠요."** 이 모듈은 지금까지 배운 모든 것(systemd, journald, 시그널·포트 추적, 파일 권한)을 동원해 실제 장애를 처음부터 끝까지 수습하는 종합 시나리오입니다.

이번에는 명령을 일일이 알려주지 않습니다 — **진단 순서**가 이 모듈의 학습 목표입니다. 막히면 이전 모듈의 도구를 떠올리세요: `systemctl status/cat`, `journalctl -u`, `sudo ss -ltnp`, `ls -l`, `sudo -u <user>`.

현재 상황부터 파악합시다.

```
systemctl status lab-app --no-pager
```

- `Active:` 줄(상태)과 마지막 로그 몇 줄에서 첫 단서를 찾는다. `--no-pager` 는 less 없이 바로 출력.

## 기동 실패 진단 — 203/EXEC

status만으로 부족하면 journal이 정답을 알고 있습니다.

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <유닛>` — 그 유닛의 로그만. `| tail -20` 으로 최근 20줄에 집중한다.

`status=203/EXEC` — linux-06에서 만난 그 코드입니다. 유닛이 **무엇을 실행하려다** 실패했는지 확인하세요.

```
systemctl cat lab-app
```

- 유닛 파일 내용을 그대로 본다. `ExecStart=`(무엇을 실행하나)와 `User=`(누구로 실행하나)를 눈여겨보자.

ExecStart의 인터프리터 경로가 이 시스템에 실제로 존재하는지 대조해 보세요 (`ls /usr/bin/python3*`). 존재하지 않는 버전을 가리키고 있을 겁니다 — 배포 스크립트가 다른 서버 기준으로 쓰인 흔한 사고입니다.

과제: ExecStart를 실재하는 인터프리터로 고치고 `daemon-reload` 하세요. 고쳤으면 **[체크]**.

> 아직 start는 성공하지 않습니다 — 장애는 보통 한 겹이 아닙니다. 다음 단계로.

## 포트 충돌 해결

이제 start 하면 다른 에러가 납니다.

서비스 시작 시도:

```
sudo systemctl start lab-app
```

- 수리 후 다시 기동해 본다. 실패하면 다음 로그가 새 원인을 알려 준다.

에러 로그 확인:

```
journalctl -u lab-app --no-pager | tail -5
```

- 방금 시도의 로그만 보면 되므로 마지막 5줄.

`Address already in use` — lab-app이 쓸 8080을 **누군가 선점**하고 있습니다. linux-02·07에서 배운 포트 추적으로 범인을 찾으세요.

```
sudo ss -ltnp | grep 8080
```

- 8080 에서 리스닝 중인 소켓과 그 프로세스(`users:(("이름",pid=…))`)를 찾는다. PID 를 기억해 두자.

PID를 유닛으로 역추적하려면 `systemctl status <PID>`가 편리합니다. 범인은 폐기 예정인 레거시 유닛입니다. 정지만 하면 재부팅 때 되살아나니 **disable까지** 해야 합니다.

과제: 선점 유닛을 `disable --now`로 내리고 lab-app을 기동하세요. lab-app이 active가 되면 **[체크]**.

## 권한 문제 해결

서비스는 떴는데... 아직 끝이 아닙니다.

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — 응답 본문 앞에 상태 줄(`HTTP/1.0 404 …`)과 헤더도 함께(include) 출력한다.

**404** — 그런데 파일은 분명히 있습니다 (`ls -l /srv/lab-app/`). 왜일까요?

단서는 두 가지입니다. ① 유닛에 `User=labapp`이 있습니다 — 서비스는 root가 아니라 labapp으로 돕니다. ② index.html은 `root:root 600` — **labapp이 읽을 수 없습니다.** 이 서버(http.server)는 파일을 못 열면 404를 냅니다. "파일이 있는데 404"의 전형적인 권한 문제입니다.

의심을 검증하는 습관 — 그 사용자 입장에서 직접 읽어 보세요.

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <사용자> <명령>` — 그 사용자 권한으로 명령을 실행한다. 서비스가 보는 것과 같은 권한으로 파일을 읽어 보는 검증법이다.

과제: labapp이 읽을 수 있도록 소유권 또는 권한을 고치세요 (linux-01의 감각으로 — 필요 이상 열지 말 것). curl이 `LAB APP OK`를 반환하면 **[체크]**.

## 재발 방지와 마무리

복구는 "지금 되게" + **"다음에도 되게"**까지가 한 세트입니다. 체크리스트:

1. lab-app이 **enable** 상태인가? (재부팅하면 다시 죽는 복구는 복구가 아닙니다)
2. 최종 응답을 증거로 남기기 — `~/work/final.txt`에 저장

부팅 자동 기동 등록:

```
sudo systemctl enable lab-app
```

- `enable` — 부팅 시 자동 기동 등록(심볼릭 링크 생성). 지금 도는 서비스에는 영향이 없다. `systemctl is-enabled lab-app` 으로 확인.

최종 응답 저장:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- `curl -s` 로 받은 응답 본문을 `>` 로 파일에 저장한다.

저장된 내용 확인:

```
cat ~/work/final.txt
```

- 저장된 응답이 `LAB APP OK` 인지 확인한다.

**[체크]** 하면 리눅스 트랙 완주입니다. 오늘 수습한 3중 장애(잘못된 경로 → 포트 충돌 → 권한)는 실제 장애 리포트에서 가장 흔한 조합이라는 것, 그리고 그 셋 모두 **journal과 ss와 ls -l이 먼저 알고 있었다**는 걸 기억하세요.
