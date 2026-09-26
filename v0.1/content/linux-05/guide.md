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

- `getent <데이터베이스> <키>` — NSS 를 통해 항목 하나를 조회한다. `passwd` 데이터베이스에서 `learner` 줄을 출력한다.

shadow 앞부분 보기:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` 는 root 만 읽을 수 있어 `sudo` 가 필요하다. 두 번째 필드가 비밀번호 해시(`*`·`!` 는 로그인 불가).

> `getent`는 파일을 직접 여는 대신 NSS(LDAP 등 외부 소스 포함)를 통해 조회합니다 — `cat /etc/passwd`보다 정확한 습관입니다.

## 사용자 생성

배포 담당 계정 `deploy`를 만드세요. 요구사항:

- 홈 디렉터리 생성 (`-m` — 안 주면 홈 없는 계정이 됩니다)
- 로그인 셸 `/bin/bash` (`-s` — 배포판 기본값은 sh인 경우가 많습니다)

deploy 사용자 생성:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — 새 사용자 생성. `-m` 홈 디렉터리 생성(`/etc/skel` 내용 복사), `-s /bin/bash` 로그인 셸 지정, 마지막 인자가 사용자 이름.
- 비밀번호는 따로 `passwd deploy` 로 정한다(이 랩에선 필요 없음).

passwd 항목 확인:

```
getent passwd deploy
```

- 콜론으로 구분된 필드 중 마지막 두 개가 홈 디렉터리와 셸이다. `/home/deploy`, `/bin/bash` 인지 확인.

홈 디렉터리 확인:

```
ls -ld /home/deploy
```

- `ls -ld` — 디렉터리 안 내용이 아니라 디렉터리 **자체**(`-d`)의 권한·소유자를 본다. 소유자가 `deploy` 여야 한다.

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

- `groupadd <그룹>` — 새 그룹을 만든다. `/etc/group` 에 한 줄이 추가된다.

보조 그룹으로 추가:

```
sudo usermod -aG ops deploy
```

- `usermod` — 기존 사용자 속성 변경. `-G ops` 보조 그룹 지정, `-a` 기존 보조 그룹에 **추가**(append).
- 이미 로그인한 세션에는 다시 로그인해야 새 그룹이 반영된다.

그룹 확인:

```
id deploy
```

- `id <사용자>` — UID, 1차 그룹(`gid=`), 모든 그룹(`groups=`) 을 한 줄로 보여 준다.

`id` 출력에서 `gid=`(1차)와 `groups=`(전체)를 구분해 읽어 보세요. 확인했으면 **[체크]** 하세요.

## sudoers 최소권한

deploy에게 서비스 상태 조회를 허용하되 **그 이상은 금지**하려 합니다. 규칙은 `/etc/sudoers`를 직접 고치지 말고 `/etc/sudoers.d/` 아래 드롭인으로 만드는 것이 관례입니다.

문법: `누가 어디서=(누구로) [NOPASSWD:] 명령들`

드롭인 규칙 작성:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo '규칙' | sudo tee <파일>` — `sudo echo … > 파일` 은 리다이렉트를 내 셸이 처리해 권한 오류가 난다. 그래서 root 로 도는 `tee` 가 파일에 쓰게 한다.
- 규칙: `deploy` 가 모든 호스트(`ALL`)에서 누구로든(`(ALL)`) 비밀번호 없이(`NOPASSWD:`) `systemctl status *` 만 실행 가능.

권한을 440 으로:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — 소유자(root)·그룹 읽기 전용. sudo 는 다른 사용자에게 쓰기 권한이 있는 sudoers 파일을 거부한다.

**문법 검증은 필수입니다.** sudoers가 깨지면 sudo 자체가 먹통이 되어 복구가 곤란해집니다. `visudo -cf`가 그 안전장치입니다.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — 문법 검사만(check), `-f <파일>` — 검사할 파일 지정. `parsed OK` 가 나와야 한다.
- 원래 sudoers 편집은 `sudo visudo`(저장 전 자동 검사)로 하는 것이 정석이다.

deploy 입장에서 뭐가 되는지 확인해 봅시다.

deploy 의 sudo 권한 목록:

```
sudo -l -U deploy
```

- `sudo -l` — 허용된 sudo 명령 목록, `-U deploy` — 다른 사용자의 목록을 조회한다(root 권한 필요).

허용된 명령 — 성공해야 합니다:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # 허용된 것
```

- `sudo -u deploy <명령>` — deploy 사용자로 명령을 실행한다. 그 안에서 다시 `sudo` 를 불러 deploy 의 sudo 권한을 시험한다.
- `sudo -n` — 비밀번호를 묻지 않는다(non-interactive). 물어봐야 하는 상황이면 바로 실패한다.
- `--no-pager` — 출력을 less 로 넘기지 않고 바로 찍는다.

금지된 명령 — 거부되어야 합니다:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # 거부되는 것
```

- 규칙에 없는 `restart` 이므로 거부된다. `2>&1` 로 에러 메시지도 파이프로 넘겨 `tail -1` 로 마지막 줄만 본다.

허용/거부가 의도대로면 **[체크]** 하세요.

## 계정 잠금과 비밀번호 정책

`olduser`는 퇴사자 계정입니다. 삭제(`userdel`)는 파일 소유권 정리 문제가 있어 보통 **잠금**부터 합니다.

계정 잠금:

```
sudo usermod -L olduser
```

- `usermod -L` — 계정 잠금(Lock). shadow 의 해시 앞에 `!` 를 붙여 비밀번호 로그인을 막는다. 해제는 `-U`.

잠금 상태 확인:

```
sudo passwd -S olduser
```

- `passwd -S <사용자>` — 비밀번호 상태 요약. 두 번째 필드 `L` 잠김, `P` 사용 가능, `NP` 비밀번호 없음.

`passwd -S` 두 번째 필드가 `L`(locked)이면 성공입니다. 잠금은 shadow의 해시 앞에 `!`를 붙이는 것뿐이라 언제든 `-U`로 되돌릴 수 있습니다.

이어서 deploy에게 비밀번호 **최대 사용 기간 90일** 정책을 적용하세요.

최대 90일 정책 적용:

```
sudo chage -M 90 deploy
```

- `chage` — 비밀번호 만료 정책(change age) 변경. `-M 90` — 최대 사용 일수를 90일로.

정책 확인:

```
sudo chage -l deploy
```

- `chage -l` — 마지막 변경일·만료일·최대/최소 기간 등 현재 정책을 목록(list)으로 보여 준다.

두 가지 모두 확인했으면 **[체크]** — 모듈 완료입니다.
