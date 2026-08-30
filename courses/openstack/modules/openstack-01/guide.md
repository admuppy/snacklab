# 첫 인스턴스 띄우기

이 랩은 파드 안에 뜬 **당신 전용 올인원 OpenStack**(Caracal)에서 진행한다. keystone·glance·
neutron·nova가 모두 이 안에서 돌고 있고, 터미널에는 관리자 자격증명이 이미 설정되어 있어
`openstack` CLI를 바로 쓸 수 있다(`os` 별칭도 있다).

> 참고: 이 랩의 nova는 **fake 드라이버**로 동작한다 — 인스턴스는 실제 VM 없이 상태 머신으로만
> 기동되므로 즉시 뜨고 자원을 거의 쓰지 않는다. 콘솔 접속·SSH는 되지 않지만, API·CLI 흐름은
> 실제 OpenStack과 동일하다.

서비스 카탈로그 확인:

```bash
openstack service list
```

컴퓨트 호스트 확인:

```bash
openstack compute service list
```

> 참고: [OpenStack CLI 문서](https://docs.openstack.org/python-openstackclient/latest/)

## 1. 네트워크와 서브넷 생성

인스턴스를 붙일 테넌트 네트워크부터 만든다.

네트워크 `net1` 생성:

```bash
openstack network create net1
```

`192.168.100.0/24` 대역의 서브넷 `subnet1` 을 `net1` 에 생성:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

만들어진 네트워크 확인:

```bash
openstack network list
```

## 2. 인스턴스 기동 (ACTIVE)

준비된 `cirros` 이미지와 `m1.tiny` 플레이버로 인스턴스 `vm1` 을 기동한다.

사용 가능한 이미지 확인:

```bash
openstack image list
```

플레이버 확인:

```bash
openstack flavor list
```

인스턴스 기동:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

상태가 `ACTIVE` 가 될 때까지 확인(몇 초 걸릴 수 있다):

```bash
openstack server show vm1 -c status -c addresses
```

## 3. 인스턴스 정지 (SHUTOFF)

기동된 인스턴스를 정지해 라이프사이클을 마무리한다.

인스턴스 정지:

```bash
openstack server stop vm1
```

상태가 `SHUTOFF` 인지 확인:

```bash
openstack server show vm1 -c status
```
