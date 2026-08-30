# 텍스트 처리 파이프라인

리눅스 운영의 절반은 **로그 읽기**입니다. grep·awk·sed 세 도구를 파이프로 엮으면 수십만 줄 로그에서 몇 초 만에 답을 뽑아낼 수 있습니다.

실습 환경에는 웹서버 액세스 로그 2,000줄이 준비되어 있습니다. 먼저 생김새를 봅시다.

앞 5줄 보기:

```
head -5 /var/log/lab/access.log
```

전체 라인 수 확인:

```
wc -l /var/log/lab/access.log
```

한 줄의 구조 (공백 기준 필드 번호):

| 필드 | 내용 | 예 |
|---|---|---|
| $1 | 클라이언트 IP | `192.168.14.23` |
| $6~$8 | 요청 (`"METHOD path HTTP/1.1"`) | `"GET /api/users HTTP/1.1"` |
| $9 | 상태 코드 | `200` |
| $10 | 응답 바이트 | `1532` |

## grep으로 오류 찾기

grep은 패턴에 맞는 **라인을 골라내는** 도구입니다. 서버 오류(5xx)를 찾아봅시다. 단순히 `grep 500`을 하면 바이트 수가 500인 라인도 걸립니다 — **상태 코드 자리만** 매칭해야 합니다.

```
grep -E '" 5[0-9]{2} ' /var/log/lab/access.log | head
```

`"` 뒤 공백 다음의 5xx만 매칭하도록 앞뒤 문맥을 넣은 것이 핵심입니다. `-c`는 매칭 라인 수만 출력합니다.

과제: 5xx 오류 라인 수를 `~/work/err5xx.count`에 저장하세요.

5xx 라인 수 저장:

```
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
```

저장 값 확인:

```
cat ~/work/err5xx.count
```

저장했으면 **[체크]** 하세요.

## awk로 필드 추출과 집계

awk는 라인을 **필드로 쪼개서** 다루는 도구입니다. `$1`이 첫 필드(IP)입니다.

```
awk '{print $1}' /var/log/lab/access.log | head
```

여기에 고전 집계 파이프라인 `sort | uniq -c | sort -rn`을 붙이면 빈도표가 됩니다.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn
```

> `uniq -c`는 **인접한** 중복만 세므로 반드시 `sort`가 먼저 와야 합니다.

과제: 요청이 가장 많은 IP **하나만** (IP 문자열만, 건수 제외) `~/work/top-ip.txt`에 저장하세요. `head -1`로 첫 줄을 뜯고 awk로 IP 필드만 다시 추출하면 됩니다.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
```

저장했으면 **[체크]** 하세요.

## sed로 스트림 편집

이 로그를 외부에 공유해야 하는데 클라이언트 IP는 개인정보라 **마스킹**이 필요합니다. sed의 치환(`s/패턴/치환/`)으로 해결합니다.

정규식으로 라인 첫머리의 IPv4를 잡습니다. `-E`(확장 정규식)를 쓰면 `{1,3}` 수량자를 그대로 쓸 수 있습니다.

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log | head -3
```

과제: 전체 로그의 IP를 `REDACTED`로 치환한 사본을 `~/work/access-redacted.log`로 저장하세요. 라인 수는 원본과 같아야 합니다 (삭제가 아니라 치환).

치환 사본 저장:

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
```

치환된 라인 수 확인:

```
grep -c REDACTED ~/work/access-redacted.log
```

저장했으면 **[체크]** 하세요.

## 파이프라인 종합

마지막은 실전형 질문입니다: **"/api 경로로 들어온 요청 중 성공(200)한 응답의 총 전송량은?"**

awk 하나로 필터와 집계를 동시에 할 수 있습니다 — 조건식으로 라인을 거르고, 변수에 누적하고, `END` 블록에서 출력합니다.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log
```

풀어 보면:

| 조각 | 의미 |
|---|---|
| `$7 ~ /^\/api\//` | 경로 필드가 `/api`로 시작 |
| `&& $9 == 200` | 그리고 상태가 200 |
| `{s += $10}` | 바이트 필드를 s에 누적 |
| `END {print s}` | 다 읽은 뒤 합계 출력 |

과제: 이 합계를 `~/work/api-bytes.txt`에 저장하고 **[체크]** 하세요.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log > ~/work/api-bytes.txt
```
