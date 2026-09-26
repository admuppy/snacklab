# qcow2 이미지 만들어 올리기

인스턴스는 **이미지**에서 시작한다. 이미지는 운영체제가 설치된 디스크를 파일 하나로 굳혀 둔 것이고,
glance가 그 파일을 보관한다. 이 랩에서는 디스크 파일을 직접 만들고 포맷을 바꾼 뒤, glance에 올려
그 이미지로 인스턴스를 띄운다.

**qcow2**(QEMU Copy On Write 2)는 OpenStack에서 가장 널리 쓰는 디스크 포맷이다. 두 가지 성질이
핵심이다.

- **희소 할당(sparse)** — 가상 크기가 1GiB라도 실제로 쓴 데이터만큼만 파일을 차지한다. 그래서
  이미지를 주고받을 때 전송량이 작다.
- **메타데이터를 갖는다** — 백킹 파일, 스냅샷, 압축 같은 정보를 파일 안에 담을 수 있다.

반대로 **raw**는 디스크의 바이트를 그대로 늘어놓은 포맷이다. 구조가 없어 다루기 단순하고 I/O가
한 겹 덜 거치지만, 파일 크기가 가상 크기만큼 잡히는 것이 보통이다. 운영에서는 "배포는 qcow2,
스토리지에 올릴 때는 raw"로 쓰는 경우가 많다.

> 참고: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> 참고: 이 랩의 nova는 fake 드라이버라 인스턴스 안에서 OS가 실제로 부팅하지는 않는다. 이미지가
> 올바르게 등록되고 nova가 그 이미지로 인스턴스를 만드는 흐름까지가 확인 대상이다.

작업할 디렉터리는 `~/images` 로, 부트스트랩이 미리 만들어 두었다. 인스턴스를 붙일 네트워크
`net1` 도 준비돼 있다.

## 1. 빈 qcow2 디스크 만들기

`qemu-img` 는 디스크 이미지를 만들고 변환하는 도구다. 먼저 아무것도 들어 있지 않은 qcow2 디스크를
하나 만들어 파일 구조를 살펴본다.

가상 크기 1GiB의 빈 qcow2 디스크 생성:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — 새 디스크 이미지 파일을 만든다.
- `-f qcow2` — 만들 파일의 포맷, 이어서 파일 경로, 마지막 `1G` — 게스트가 보게 될 가상 크기.

만든 디스크의 정보 확인:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — 이미지의 포맷(`file format`), 가상 크기, 실제 크기, 클러스터 크기 등 메타데이터를 보여 준다.

`virtual size` 는 게스트가 보게 될 디스크 크기이고, `disk size` 는 파일이 실제로 차지하는 크기다.
방금 만든 디스크는 내용이 없으므로 둘의 차이가 크다. 이것이 희소 할당이다.

파일이 실제로 얼마나 차지하는지 확인:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — 파일의 상세 정보(권한·소유자·크기·시각), `-h` — 크기를 K/M/G 처럼 사람이 읽기 좋은 단위로.
- 여기서 보이는 크기는 파일의 "겉보기" 크기다. 실제 점유 블록은 `du -h` 로 볼 수 있다.

## 2. 디스크 포맷 변환 (qcow2 ↔ raw)

이번에는 진짜 OS가 들어 있는 디스크를 다룬다. glance에 이미 있는 `cirros` 이미지를 내려받아
포맷을 바꿔 본다.

glance에 등록된 이미지의 포맷 확인:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <이름>` — glance 이미지의 속성. `-c` 로 `disk_format`·`container_format`·`size`(바이트) 열만 고른다.

`disk_format` 은 디스크 파일 자체의 포맷(qcow2·raw·vmdk…)이고, `container_format` 은 그 디스크를
감싼 메타데이터 봉투를 뜻한다. 봉투 없이 디스크만 올릴 때 쓰는 값이 `bare` 이며, 실무에서 대부분
이 값을 쓴다.

이미지 파일을 로컬로 내려받기:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <이름> --file <경로>` — glance 에 저장된 이미지 데이터를 로컬 파일로 내려받는다. 이름과 달리 "다운로드" 명령이다.

내려받은 파일의 포맷 확인:

```bash
qemu-img info ~/images/cirros-src.img
```

- 확장자가 `.img` 여도 실제 포맷은 내용으로 판별된다. `file format` 줄을 확인하자.

qcow2를 raw로 변환(`-f` 는 원본 포맷, `-O` 는 출력 포맷):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — 이미지를 다른 포맷으로 복사 변환한다(원본은 그대로).
- `-f qcow2` — 입력 포맷(소문자 f), `-O raw` — 출력 포맷(대문자 O). 그다음 원본 경로, 대상 경로 순.

변환된 raw 디스크 확인:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw 는 메타데이터가 없어 `file format: raw` 와 크기 정보 정도만 나온다.

raw는 구조가 없으므로 `disk size` 가 `virtual size` 에 가깝게 잡힌다. 이 상태로는 전송에 불리하니
다시 qcow2로 되돌린다.

raw를 다시 qcow2로 변환:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 이번엔 입력 raw → 출력 qcow2. 비어 있는 블록은 기록하지 않아 파일이 다시 작아진다. (`-c` 를 더하면 압축까지 한다.)

세 파일의 크기를 한눈에 비교:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- 여러 파일을 한 번에 나열해 원본·raw·재변환 qcow2 의 크기를 나란히 비교한다.

## 3. glance에 올리고 인스턴스 기동

만든 qcow2 파일을 glance에 등록한다. 업로드할 때는 **디스크 포맷과 컨테이너 포맷을 반드시 맞게**
지정해야 한다. 실제 파일은 qcow2인데 `--disk-format raw` 로 올리면 등록은 되지만 부팅에서 깨진다.

함께 지정하는 값들의 뜻은 다음과 같다.

- `--min-disk` / `--min-ram` — 이 이미지를 쓰려면 최소한 얼마의 디스크·메모리가 필요한지 알리는
  힌트다. 조건에 못 미치는 플레이버는 nova가 걸러 낸다.
- `--property` — 임의의 메타데이터를 붙인다. `os_distro` 처럼 표준으로 쓰이는 키는 스케줄링이나
  하이퍼바이저 설정에 쓰이기도 한다.

qcow2 파일을 glance 이미지로 등록:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — 새 glance 이미지 `cirros-lab` 을 등록한다.
- `--disk-format qcow2 --container-format bare` — 파일의 실제 포맷과 봉투(없음).
- `--min-disk 1 --min-ram 64` — 필요한 최소 디스크(GB)·메모리(MB), `--property os_distro=cirros` — 임의 메타데이터.
- `--file <경로>` — 업로드할 로컬 파일. 업로드가 끝나야 `status` 가 `active` 가 된다.

등록 결과 확인(`status` 가 `active` 여야 한다):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- 등록 시 준 값들이 그대로 저장됐는지 필요한 열만 골라 확인한다. `--property` 로 준 값은 `properties` 에 들어 있다.

이미지 목록에서도 확인:

```bash
openstack image list
```

- 목록에 `cirros-lab` 이 `active` 로 보이면 인스턴스에 쓸 수 있다.

직접 만든 이미지로 인스턴스 `vm2` 기동:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- 1번 모듈과 같은 형식이지만 `--image cirros-lab` 으로 직접 만든 이미지를 지정한다. 플레이버 조건이 `--min-disk`/`--min-ram` 을 만족해야 생성된다.

상태와 사용된 이미지 확인:

```bash
openstack server show vm2 -c status -c image
```

- `image` 열에 `cirros-lab` 과 그 ID 가 나오면 방금 올린 이미지로 만들어진 것이다.
