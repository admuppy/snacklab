# 네트워킹 진단

"서비스가 안 붙어요"의 원인은 대부분 네 가지 중 하나입니다 — **IP가 다르다, 포트가 안 열렸다, 바인딩이 잘못됐다, 이름이 안 풀린다.** 이 모듈에서는 그 네 가지를 순서대로 진단하는 도구(ip, ss, curl, getent)를 익힙니다.

실습 환경에는 `lab-api`라는 API 서비스가 떠 있습니다 — 그런데 "밖에서 접속이 안 된다"는 신고가 들어와 있는 상태입니다. 끝까지 가면 원인을 찾아 고치게 됩니다.

## 인터페이스와 IP 조사

네트워크 진단의 출발점은 **내가 누구인지**(IP) 확인하기입니다. 요즘 표준 도구는 `ip`입니다 (ifconfig는 은퇴했습니다).

인터페이스 목록 확인:

```
ip link
```

IPv4 주소 확인:

```
ip -4 addr show
```

라우팅 테이블 확인:

```
ip route
```

컨테이너에는 보통 `lo`(루프백)와 `eth0` 두 개가 보입니다. 스크립트에서 쓰기 좋은 한 줄 추출 방법:

eth0 을 한 줄로 출력:

```
ip -4 -o addr show eth0
```

CIDR 필드만 추출:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

과제: eth0의 IPv4 주소를 **CIDR 없이 주소만** `~/work/myip.txt`에 저장하세요. `/24` 같은 접미사는 `cut -d/ -f1`로 떼어냅니다.

주소만 떼어 저장:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

저장된 내용 확인:

```
cat ~/work/myip.txt
```

저장했으면 **[체크]** 하세요.

## 리스닝 소켓 추적

다음 질문: **무엇이 어떤 포트에서 듣고 있나.** `ss`의 필수 조합부터.

| 옵션 | 의미 |
|---|---|
| `-l` | 리스닝 소켓만 |
| `-t` / `-u` | TCP / UDP |
| `-n` | 포트를 숫자로 (서비스명 변환 생략) |
| `-p` | 프로세스 표시 (남의 것은 sudo 필요) |

```
sudo ss -ltnp
```

과제: `lab-api.service`가 리스닝하는 **포트 번호**를 찾아 `~/work/api-port.txt`에 저장하세요. 유닛의 메인 PID에서 출발하는 것도 좋은 경로입니다.

lab-api 의 메인 PID 확인:

```
systemctl show -p MainPID --value lab-api
```

그 PID의 리스닝 소켓 찾기:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

Local Address 열의 `127.0.0.1:포트`에서 포트만 읽으면 됩니다. 저장 후 **[체크]** 하세요.

## 바인딩 문제 진단과 수리

방금 ss 출력에서 눈치챘을 수도 있습니다 — lab-api의 Local Address가 `127.0.0.1:9090`입니다. **루프백에만 바인딩**되어 있으니 이 컨테이너 안에서는 되고, 밖(다른 pod, 노드)에서는 connection refused가 나는 겁니다. 재현해 봅시다.

루프백으로 접속:

```
curl -s http://127.0.0.1:9090/status.json        # 성공
```

컨테이너 IP로 접속:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # 실패!
```

같은 프로세스인데 **어느 주소로 들어오느냐**에 따라 결과가 다릅니다. `0.0.0.0`(모든 인터페이스)으로 바인딩을 바꿔야 합니다.

과제: 유닛 파일의 `--bind 127.0.0.1`을 `--bind 0.0.0.0`으로 고치고 재기동하세요.

유닛 파일 수정:

```
sudo vim /etc/systemd/system/lab-api.service
```

변경 사항 리로드:

```
sudo systemctl daemon-reload
```

서비스 재시작:

```
sudo systemctl restart lab-api
```

바인딩 주소 확인:

```
sudo ss -ltn | grep 9090
```

컨테이너 IP로 다시 접속:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # 이제 성공
```

`0.0.0.0:9090`으로 바뀌고 컨테이너 IP로 응답하면 **[체크]** 하세요.

## 이름 해석 — hosts와 DNS

마지막 조각은 **이름 → IP**입니다. 해석 순서는 보통 `/etc/hosts` → DNS(`/etc/resolv.conf`의 네임서버)이며, 그 순서 규칙은 `/etc/nsswitch.conf`의 `hosts:` 줄이 정합니다.

DNS 서버 설정 확인:

```
cat /etc/resolv.conf
```

해석 순서 규칙 확인:

```
grep hosts /etc/nsswitch.conf
```

조회 도구는 용도가 다릅니다: `nslookup`/`dig`는 **DNS 서버에 직접** 묻고, `getent hosts`는 **시스템의 실제 해석 경로**(hosts 파일 포함)를 따릅니다. 애플리케이션이 보는 결과는 getent 쪽입니다.

과제: `api.lab.local`이라는 이름으로 lab-api에 접근할 수 있게 하세요. DNS 서버를 고칠 수는 없으니 `/etc/hosts`에 등록합니다.

hosts 파일에 이름 등록:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

시스템 해석 경로로 조회:

```
getent hosts api.lab.local
```

이름으로 접속:

```
curl -s http://api.lab.local:9090/status.json
```

응답이 오면 **[체크]** — 모듈 완료입니다.
