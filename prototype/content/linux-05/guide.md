# 사용자·그룹과 sudo 최소권한

서버에 새 동료가 오면 계정을 만들고, 팀 그룹에 넣고, **필요한 만큼만** sudo를 열어 줍니다. 퇴사하면 계정을 잠급니다. 이 모듈은 그 전체 수명주기를 다룹니다.

계정 정보가 어디 저장되는지부터 봅시다.

| 파일 | 내용 |
|---|---|
| `/etc/passwd` | 사용자 목록 (이름:x:UID:GID:설명:홈:셸) |
| `/etc/shadow` | 비밀번호 해시 + 만료 정책 (root만 읽기) |
| `/etc/group` | 그룹과 구성원 |
| `/etc/sudoers`, `/etc/sudoers.d/` | sudo 권한 규칙 |

learner 계정 조회:

```
getent passwd learner
```

shadow 앞부분 보기:

```
sudo head -3 /etc/shadow
```

> `getent`는 파일을 직접 여는 대신 NSS(LDAP 등 외부 소스 포함)를 통해 조회합니다 — `cat /etc/passwd`보다 정확한 습관입니다.

## 사용자 생성

배포 담당 계정 `deploy`를 만드세요. 요구사항:

- 홈 디렉터리 생성 (`-m` — 안 주면 홈 없는 계정이 됩니다)
- 로그인 셸 `/bin/bash` (`-s` — 배포판 기본값은 sh인 경우가 많습니다)

deploy 사용자 생성:

```
sudo useradd -m -s /bin/bash deploy
```

passwd 항목 확인:

```
getent passwd deploy
```

홈 디렉터리 확인:

```
ls -ld /home/deploy
```

`useradd`는 저수준 도구라 **아무것도 물어보지 않습니다**. 옵션을 빠뜨리면 그냥 그대로 만들어 버리니 만든 뒤 확인이 필수입니다. 확인했으면 **[체크]** 하세요.

## 그룹 구성

운영팀 그룹 `ops`를 만들고 deploy를 넣습니다. 여기서 고전적인 함정 하나 —

| 명령 | 결과 |
|---|---|
| `usermod -aG ops deploy` | ops를 **보조 그룹으로 추가** ✔ |
| `usermod -G ops deploy` | 보조 그룹을 ops **하나로 교체** (기존 것 다 빠짐!) |
| `usermod -g ops deploy` | **1차 그룹을 교체** (파일 생성 기본 그룹이 바뀜) |

`-a`(append) 없는 `-G`는 사고의 지름길입니다. 보조 그룹으로 추가하세요.

ops 그룹 생성:

```
sudo groupadd ops
```

보조 그룹으로 추가:

```
sudo usermod -aG ops deploy
```

그룹 확인:

```
id deploy
```

`id` 출력에서 `gid=`(1차)와 `groups=`(전체)를 구분해 읽어 보세요. 확인했으면 **[체크]** 하세요.

## sudoers 최소권한

deploy에게 서비스 상태 조회를 허용하되 **그 이상은 금지**하려 합니다. 규칙은 `/etc/sudoers`를 직접 고치지 말고 `/etc/sudoers.d/` 아래 드롭인으로 만드는 것이 관례입니다.

문법: `누가 어디서=(누구로) [NOPASSWD:] 명령들`

드롭인 규칙 작성:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

권한을 440 으로:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

**문법 검증은 필수입니다.** sudoers가 깨지면 sudo 자체가 먹통이 되어 복구가 곤란해집니다. `visudo -cf`가 그 안전장치입니다.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

deploy 입장에서 뭐가 되는지 확인해 봅시다.

deploy 의 sudo 권한 목록:

```
sudo -l -U deploy
```

허용된 명령 — 성공해야 합니다:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # 허용된 것
```

금지된 명령 — 거부되어야 합니다:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # 거부되는 것
```

허용/거부가 의도대로면 **[체크]** 하세요.

## 계정 잠금과 비밀번호 정책

`olduser`는 퇴사자 계정입니다. 삭제(`userdel`)는 파일 소유권 정리 문제가 있어 보통 **잠금**부터 합니다.

계정 잠금:

```
sudo usermod -L olduser
```

잠금 상태 확인:

```
sudo passwd -S olduser
```

`passwd -S` 두 번째 필드가 `L`(locked)이면 성공입니다. 잠금은 shadow의 해시 앞에 `!`를 붙이는 것뿐이라 언제든 `-U`로 되돌릴 수 있습니다.

이어서 deploy에게 비밀번호 **최대 사용 기간 90일** 정책을 적용하세요.

최대 90일 정책 적용:

```
sudo chage -M 90 deploy
```

정책 확인:

```
sudo chage -l deploy
```

두 가지 모두 확인했으면 **[체크]** — 모듈 완료입니다.
