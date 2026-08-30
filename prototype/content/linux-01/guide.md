# 파일 권한과 특수 권한

리눅스 보안의 첫 단추는 **파일 권한**입니다. 이 모듈에서는 기본 권한(rwx)과 umask, setgid·sticky bit 같은 특수 권한, ACL을 이용한 세밀한 접근 제어, 그리고 실제 시스템에서 위험한 권한을 찾아 고치는 감사까지 다룹니다.

현재 사용자를 확인해 봅시다. `learner`는 sudo가 가능한 일반 사용자입니다.

```
id
```

권한 표기는 두 가지를 오갈 수 있어야 합니다.

| 표기 | 예 | 의미 |
|---|---|---|
| 심볼릭 | `rwxr-x---` | 소유자 rwx / 그룹 r-x / 기타 없음 |
| 8진수 | `750` | r=4, w=2, x=1 의 합 |

## 기본 권한과 umask

파일을 만들 때 기본 권한은 **umask**가 결정합니다.

현재 umask 값 확인:

```
umask
```

파일을 하나 만들어 실제로 어떤 권한으로 생기는지 확인:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

이제 나만 접근할 수 있는 작업 공간을 만듭니다. 요구사항:

- `~/work` 디렉터리 — 권한 **700** (소유자만 rwx)
- `~/work/secret.txt` 파일 — 내용은 자유, 권한 **600** (소유자만 rw)

작업 디렉터리를 만들고 700으로:

```
mkdir -p ~/work && chmod 700 ~/work
```

비밀 파일 생성:

```
echo "top secret" > ~/work/secret.txt
```

파일 권한을 600으로:

```
chmod 600 ~/work/secret.txt
```

`stat`으로 확인하고 **[체크]** 하세요.

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

> 디렉터리의 `x`는 "통과(진입) 권한"입니다. 디렉터리에 `r`이 있어도 `x`가 없으면 안의 파일에 접근할 수 없습니다 — 3단계 ACL에서 다시 만납니다.

## setgid와 sticky bit

팀 공유 디렉터리를 만들 때 자주 쓰는 특수 권한 두 가지:

| 비트 | 8진수 | 디렉터리에서의 효과 |
|---|---|---|
| setgid | 2000 | 안에 생기는 파일이 **디렉터리의 그룹을 상속** |
| sticky | 1000 | 파일 삭제는 **소유자만** 가능 (`/tmp`와 같은 방식) |

`share` 그룹의 공유 디렉터리 `/srv/share`를 만드세요. 요구사항:

- 그룹 생성: `share`
- `/srv/share` 디렉터리, 소유 그룹 `share`
- 권한 **3775** = setgid(2000) + sticky(1000) + 775

그룹 생성:

```
sudo groupadd -f share
```

공유 디렉터리 생성:

```
sudo mkdir -p /srv/share
```

소유 그룹을 share 로:

```
sudo chgrp share /srv/share
```

특수 권한 포함 3775 로:

```
sudo chmod 3775 /srv/share
```

결과를 확인해 보세요. 심볼릭 표기에서 setgid는 그룹 자리의 `s`, sticky는 마지막 자리의 `t`로 나타납니다 (`drwxrwsr-t`).

```
stat -c '%a %G %n' /srv/share && ls -ld /srv/share
```

확인했으면 **[체크]** 하세요.

## ACL로 세밀한 접근 제어

`rwx`는 소유자/그룹/기타 3칸뿐입니다. "이 파일을 **특정 사용자 한 명**에게만 읽기 허용"은 **ACL**(Access Control List)로 해결합니다.

시스템에 감사 담당 계정 `audit`이 준비되어 있습니다. 1단계에서 만든 `~/work/secret.txt`를 audit에게 **읽기 전용**으로 열어 주세요.

audit 에게 읽기 ACL 부여:

```
setfacl -m u:audit:r ~/work/secret.txt
```

걸린 ACL 확인:

```
getfacl ~/work/secret.txt
```

그런데 이걸로 끝이 아닙니다 — audit이 파일까지 **도달**하려면 경로상의 디렉터리(`~`와 `~/work`)를 통과할 수 있어야 합니다. 700 디렉터리는 audit을 막습니다.

통과(x) 권한만 ACL로 열기:

```
setfacl -m u:audit:x ~ ~/work
```

audit 입장에서 실제로 되는지 검증해 봅시다.

읽기 — 성공해야 합니다:

```
sudo -u audit cat ~/work/secret.txt
```

쓰기 — 실패해야 합니다:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

ACL이 걸린 파일은 `ls -l`에서 권한 뒤에 `+`가 붙습니다. 확인 후 **[체크]** 하세요.

## 권한 감사와 수리

마지막으로 실무형 과제입니다. **SUID**(4000) 비트가 붙은 실행 파일은 소유자(대개 root) 권한으로 실행되므로 감사 대상 1순위입니다.

시스템 전체에서 SUID 파일을 찾아 저장:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

목록 확인:

```
cat ~/work/suid.txt
```

`passwd`가 왜 SUID인지 생각해 보세요 — 일반 사용자가 root 소유인 `/etc/shadow`를 갱신해야 하기 때문입니다.

두 번째 과제: `/opt/lab/perm/danger.conf`는 DB 비밀번호가 든 설정 파일인데 권한이 **666**(누구나 읽고 쓰기!)으로 배포되어 있습니다.

현재 권한 확인:

```
ls -l /opt/lab/perm/
```

640 으로 수리:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

수리 후 **[체크]** 하면 모듈 완료입니다.
