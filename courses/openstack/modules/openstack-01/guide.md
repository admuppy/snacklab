# 첫 인스턴스 띄우기

이 랩은 파드 안에 뜬 **당신 전용 올인원 OpenStack**(Caracal)에서 진행한다. keystone·glance·
neutron·nova가 모두 이 안에서 돌고 있고, 터미널에는 관리자 자격증명이 이미 설정되어 있어
`openstack` CLI를 바로 쓸 수 있다(`os` 별칭도 있다).

> 참고: 이 랩의 nova는 **fake 드라이버**로 동작한다 — 인스턴스는 실제 VM 없이 상태 머신으로만
> 기동되므로 즉시 뜨고 자원을 거의 쓰지 않는다. 콘솔 접속·SSH는 되지 않지만, API·CLI 흐름은
> 실제 OpenStack과 동일하다.

### 서비스 카탈로그 읽기

OpenStack은 하나의 프로그램이 아니라 **역할이 다른 여러 서비스의 모음**이다. 각 서비스는
자기 REST API를 가지며, 서로를 부를 때는 keystone에 등록된 **서비스 카탈로그**에서 상대의
엔드포인트 주소를 찾는다. `openstack service list`는 그 카탈로그에 무엇이 등록돼 있는지 보여 준다.

이 랩에서 만나게 될 서비스는 다음과 같다.

| 서비스 | 타입 | 하는 일 |
|---|---|---|
| keystone | identity | 인증·권한. 로그인하면 토큰을 발급하고, 다른 서비스는 그 토큰으로 요청자를 확인한다 |
| glance | image | 인스턴스를 만들 때 쓰는 디스크 이미지를 보관·배포한다 |
| neutron | network | 네트워크·서브넷·포트 등 가상 네트워크를 담당한다 |
| nova | compute | 인스턴스(가상 머신)의 생성·기동·정지 등 라이프사이클을 맡는다 |
| placement | placement | 어느 호스트에 자원(vCPU·메모리·디스크)이 남아 있는지 추적해 nova의 배치 결정을 돕는다 |

서비스 카탈로그 확인:

```bash
openstack service list
```

- `openstack <대상> <동작>` — OpenStack CLI 의 기본 형식이다. 여기선 대상 `service`, 동작 `list`.
- keystone 서비스 카탈로그에 등록된 서비스를 나열한다. 엔드포인트 URL 까지 보려면 `openstack endpoint list`.

출력의 `Name`은 서비스 이름, `Type`은 역할을 나타내는 표준 타입 문자열이다. CLI는 이 **타입**으로
엔드포인트를 찾는다. 예를 들어 `openstack image list`는 카탈로그에서 `image` 타입을 찾아 glance를
호출한다. 즉 명령의 첫 단어(`image`·`network`·`server`…)와 여기 보이는 타입이 이어져 있다.

### 컴퓨트 서비스 구성 읽기

nova 자체도 **여러 프로세스로 쪼개져** 있다. `openstack compute service list`는 그 프로세스들이
어느 호스트에서 살아 있는지 보여 준다.

| 컴포넌트 | 하는 일 |
|---|---|
| nova-scheduler | 새 인스턴스를 **어느 컴퓨트 호스트에 놓을지** 고른다. placement가 후보를 좁혀 준다 |
| nova-conductor | DB 접근과 장시간 작업을 대신 처리한다. 컴퓨트 노드가 DB에 직접 붙지 않게 막는 중간 계층이다 |
| nova-compute | 실제 하이퍼바이저를 조작해 인스턴스를 띄우고 내린다. 컴퓨트 호스트마다 하나씩 돈다 |

컴퓨트 호스트 확인:

```bash
openstack compute service list
```

- nova 의 백그라운드 프로세스(scheduler·conductor·compute)와 그 호스트·`Status`(enabled/disabled)·`State`(up/down)를 보여 준다.

`State`가 `up`이면 그 프로세스가 살아 있다는 뜻이고, `Status`는 운영자가 꺼 둔(disabled) 상태인지를
나타낸다. 인스턴스가 `ERROR`로 떨어질 때 가장 먼저 보는 표가 이것이다 — nova-compute가 `down`이면
어떤 요청도 호스트까지 가지 못한다.

목록에 **nova-api는 보이지 않는다.** API 서비스는 웹 서버로 떠서 카탈로그(`openstack service list`)에
엔드포인트로 등록되고, 여기 나오는 것은 백그라운드 프로세스들이다. 이 랩은 올인원이라 세 컴포넌트가
모두 같은 호스트 이름으로 보인다.

> 참고: [OpenStack CLI 문서](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. 네트워크와 서브넷 생성

인스턴스를 붙일 테넌트 네트워크부터 만든다.

네트워크 `net1` 생성:

```bash
openstack network create net1
```

- neutron 에 L2 가상 네트워크 `net1` 을 만든다. 이 시점엔 IP 대역이 없어 인스턴스가 주소를 받을 수 없다 — 다음 명령의 서브넷이 필요하다.

`192.168.100.0/24` 대역의 서브넷 `subnet1` 을 `net1` 에 생성:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — 서브넷을 붙일 네트워크.
- `--subnet-range 192.168.100.0/24` — CIDR 대역. 게이트웨이(기본 `.1`)와 DHCP 할당 범위가 자동으로 정해진다.
- 마지막 인자 `subnet1` — 서브넷 이름.

만들어진 네트워크 확인:

```bash
openstack network list
```

- `Subnets` 열에 방금 붙인 서브넷 ID 가 보이면 네트워크 준비 완료.

## 2. 인스턴스 기동 (ACTIVE)

준비된 `cirros` 이미지와 `m1.tiny` 플레이버로 인스턴스 `vm1` 을 기동한다.

사용 가능한 이미지 확인:

```bash
openstack image list
```

- glance 에 등록된 이미지 목록. `Status` 가 `active` 인 이미지만 인스턴스 생성에 쓸 수 있다.

플레이버 확인:

```bash
openstack flavor list
```

- 플레이버 = 인스턴스 하드웨어 규격(vCPU·RAM·Disk) 템플릿. `m1.tiny` 가 가장 작은 규격이다.

인스턴스 기동:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — 하드웨어 규격, `--image cirros` — 부팅할 디스크 이미지, `--network net1` — 포트를 만들어 붙일 네트워크.
- 마지막 인자 `vm1` — 인스턴스 이름. 명령은 요청만 접수하고 바로 돌아오므로(`BUILD`) 상태는 따로 확인한다.

상태가 `ACTIVE` 가 될 때까지 확인(몇 초 걸릴 수 있다):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <이름>` — 인스턴스 한 개의 상세 정보.
- `-c <열>` — 출력할 열(필드)만 고른다. 여러 번 줄 수 있다. `addresses` 에는 `net1=192.168.100.x` 처럼 할당된 IP 가 나온다.

## 3. 프로젝트 전체 인스턴스 조회

지금까지 쓴 `openstack server list`는 **내가 속한 프로젝트의 인스턴스만** 보여 준다.

**프로젝트(project)** 는 OpenStack에서 자원을 소유하는 단위다(예전 이름은 tenant). 네트워크,
인스턴스, 볼륨, 이미지 같은 자원은 모두 어느 프로젝트에 속하며, 할당량(quota)도 프로젝트 단위로
걸린다. 사용자는 프로젝트에 **역할(role)** 을 부여받아 접근하고, 토큰도 "어느 프로젝트로서"
발급된다. 그래서 같은 사람이라도 어느 프로젝트로 로그인했는지에 따라 보이는 자원이 달라진다.

지금 내 토큰이 어느 프로젝트로 발급됐는지 확인:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — 현재 자격증명으로 keystone 토큰을 발급받아 그 정보를 보여 준다.
- `-c project_id -f value` — `project_id` 열만, 표 테두리 없이 값(`-f value`)으로 출력한다. 스크립트에서 쓰기 좋은 형식이다.

이 랩에는 `admin`, `service`, `demo` 같은 프로젝트가 이미 만들어져 있다. 프로젝트 목록 확인:

```bash
openstack project list
```

- keystone 에 있는 프로젝트(ID·이름) 목록. 앞 명령에서 본 `project_id` 가 어느 프로젝트인지 여기서 맞춰 볼 수 있다.

`--all-projects` 는 **모든 프로젝트의 자원을 한 번에 보여 달라**는 인자다. 클라우드 전체를 봐야 하는
운영자용 옵션이라 admin 역할이 있어야 동작하고, 일반 사용자가 쓰면 권한 오류가 난다.

모든 프로젝트의 인스턴스 조회:

```bash
openstack server list --all-projects
```

- `--all-projects` — 모든 프로젝트의 인스턴스를 조회한다(admin 역할 필요).

기본 출력에는 프로젝트 ID 열이 보이지 않는다. 어느 프로젝트의 인스턴스인지 알아야 하므로
`-c 'Project ID'` 로 그 열을 직접 골라 준다. `--long` 은 태스크 상태·호스트 같은 운영 정보를 더
붙이는 별개의 옵션이다.

프로젝트 ID를 포함해 조회:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `-c <열>` — 출력할 열(필드)만 고른다. 여러 번 줄 수 있다. 열 이름에 공백이 있으면 따옴표로 감싼다(`'Project ID'`).

채점용으로 이 결과를 파일에 남긴다:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — 표 대신 공백 구분 값만 출력한다.
- `> ~/all-servers.txt` — 그 출력을 파일로 저장(덮어쓰기)한다. 체크 스크립트가 이 파일을 읽는다.

> 참고: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. 인스턴스 정지 (SHUTOFF)

기동된 인스턴스를 정지해 라이프사이클을 마무리한다.

인스턴스 정지:

```bash
openstack server stop vm1
```

- 인스턴스를 정상 종료(전원 끄기)한다. 디스크·IP 등 자원은 그대로 남고 `openstack server start vm1` 로 다시 켤 수 있다. 완전히 지우려면 `openstack server delete`.

상태가 `SHUTOFF` 인지 확인:

```bash
openstack server show vm1 -c status
```

- `status` 가 `SHUTOFF` 로 바뀌었는지 확인한다. 바로 바뀌지 않으면 몇 초 뒤 다시 실행한다.
