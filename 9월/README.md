# Month 01 — OpenStack 인프라 기초 구축 (2025.09)

## 작업 개요

OpenStack Caracal(2024.1) 클러스터 구축의 첫 단계.

폐기 예정 서버 4대 중 3대를 Controller / Compute / Block Storage 노드로 구성하고,
자동화 도구(DevStack, Ansible 등) 없이 공식 매뉴얼 기반 수동 설치(Manual Package Installation) 방식으로 진행했다.
OS는 전 노드 Ubuntu 24.04 LTS 기반.

---

## 물리 노드 구성

| 노드 | 관리망 IP | 외부망 IP | vCPU | RAM | Disk | 역할 |
|---|---|---|---|---|---|---|
| Controller | 10.0.0.10 | 192.168.0.10 | 8 | 32G | 1T | Keystone / Glance / Placement / Nova-API / Horizon / Cinder-API / Neutron-Server |
| Compute | 10.0.0.20 | 192.168.0.20 | 8 | 32G | 1T | Nova-Compute / KVM 하이퍼바이저 |
| Block Storage | 10.0.0.30 | 192.168.0.30 | 8 | 32G | 1T | Cinder-Volume / LVM 백엔드 |

네트워크 인터페이스는 노드별로 2개 구성

- `eno1` → br-provider 브릿지에 연결 (외부망, 192.168.0.x)
- `enx68e4...` → 관리망 직접 할당 (10.0.0.x)

---

## 이달 작업 상세

### 1. 호스트 네트워크 설정 (전 노드 공통)

OpenStack 서비스 간 통신은 IP 대신 호스트 이름을 사용한다.
전 노드의 `/etc/hosts`에 아래 매핑을 동일하게 추가했다.

```
10.0.0.10  controller
10.0.0.20  compute
10.0.0.30  block
```

---

### 2. NTP 서버 구성 (chrony)

분산 시스템인 OpenStack에서 노드 간 시간 불일치는 인증 토큰 만료 오류,
로그 순서 뒤엉킴, DB 복제 실패 등 심각한 문제를 유발한다.
Controller 노드를 클러스터 기준 시간 서버로 설정하고, 나머지 노드는 Controller를 바라보도록 구성했다.

- Controller: 외부 NTP 서버(`time.bora.net`)에서 시간 수신 → 내부 클러스터에 전파
- Compute / Block: Controller(10.0.0.10)를 NTP 소스로 지정

검증 결과

```
Controller: ^* time.bora.net  Stratum 2
Compute:    ^* controller     Stratum 3
Block:      ^* controller     Stratum 3
```

---

### 3. 기반 서비스 설치

**MariaDB (중앙 데이터베이스)**

OpenStack 전 서비스의 상태 정보를 저장하는 중앙 DB.
Controller 노드에 설치하고, 바인딩 주소를 관리망 IP(10.0.0.10)로 설정했다.
스토리지 엔진은 InnoDB, 문자셋은 UTF-8로 고정.

**RabbitMQ (메시지 큐)**

서비스 간 비동기 작업 지시를 전달하는 메시지 브로커.
Nova API가 VM 생성 요청을 받으면 작업을 큐에 넣고 즉시 응답하고,
nova-scheduler가 큐에서 꺼내 처리하는 구조.

**Memcached (인증 토큰 캐시)**

Keystone 토큰 검증 요청이 매 API 호출마다 반복되므로,
인메모리 캐시로 MariaDB 부하를 줄이고 응답 속도를 향상시킨다.

**ETCD (분산 키-값 저장소)**

Neutron 등 분산 서비스가 네트워크 구성 및 서비스 상태를 일관되게 공유하기 위한 저장소.
Controller 노드 단일 구성으로 설치.

---

### 4. OpenStack 컴포넌트 설치 순서

OpenStack 수동 설치에서는 설치 순서가 매우 중요하다.
서비스 간 의존성(Keystone 없이는 다른 서비스 인증 불가)이 있기 때문.

```
Keystone → Glance → Placement → Nova → (10월: Neutron → Horizon → Cinder → Heat)
```

---

### 5. Keystone (인증 서비스)

OpenStack의 모든 서비스는 API 요청 시 Keystone을 통해 인증 토큰을 발급받아야 한다.
서비스 카탈로그를 통해 Nova, Neutron 등 각 컴포넌트의 API 엔드포인트 주소를 관리한다.

- Fernet 토큰 방식 채택 (DB 조회 없이 토큰 자체에 정보 포함)
- Apache2 + mod_wsgi로 서비스 기동
- admin / myuser 두 가지 프로젝트 및 openrc 스크립트 구성

엔드포인트 등록 (public / internal / admin 동일)

```
http://10.0.0.10:5000/v3/
```

---

### 6. Glance (이미지 서비스)

VM 인스턴스의 부팅 이미지를 저장 및 관리하는 서비스.
QCOW2, VMDK, ISO 등 다양한 포맷을 지원하며, 실제 이미지 데이터는 로컬 파일시스템에 저장.
Nova가 인스턴스를 생성할 때 Glance에서 이미지를 가져온다.

설치 후 cirros 테스트 이미지 등록으로 정상 동작 확인

```bash
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
glance image-create --name "cirros" --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare --visibility=public
```

엔드포인트: `http://10.0.0.10:9292`

---

### 7. Placement (리소스 배치 서비스)

클러스터 내 CPU / RAM / Disk 등 물리 자원 현황을 추적하는 서비스.
Nova 스케줄러가 VM 생성 요청 시 Placement에 질의하여 최적 Compute 노드를 선택한다.

검증 명령어

```bash
placement-status upgrade check
openstack --os-placement-api-version 1.2 resource class list --sort-column name
```

엔드포인트: `http://10.0.0.10:8778`

---

### 8. Nova (컴퓨트 서비스)

VM 인스턴스의 생성 / 스케줄링 / 종료 등 전체 수명 주기를 관리하는 핵심 컴포넌트.
KVM 하이퍼바이저를 추상화하여 사용자에게 통합 API를 제공한다.

**Controller 노드 설치 컴포넌트**

- `nova-api` : 외부 요청 수신
- `nova-scheduler` : 작업을 처리할 Compute 노드 선정
- `nova-conductor` : DB 접근 중개
- `nova-novncproxy` : VNC 콘솔 프록시

**Compute 노드 설치 컴포넌트**

- `nova-compute` : 실제 VM 실행 (KVM 드라이버)

DB는 3개 스키마로 구성

```
nova_api / nova / nova_cell0
```

Cell 구성 후 Compute 노드 자동 등록

```bash
nova-manage cell_v2 discover_hosts --verbose
openstack compute service list
```

---

## 설정 파일 목록

| 파일 | 노드 | 설명 |
|---|---|---|
| `configs/chrony-controller.conf` | Controller | 외부 NTP 수신 및 클러스터 전파 설정 |
| `configs/chrony-node.conf` | Compute / Block | Controller를 NTP 소스로 지정 |
| `configs/etcd.conf` | Controller | 분산 키-값 저장소 설정 |
| `configs/keystone.conf` | Controller | 인증 서비스 설정 (Fernet 토큰) |
| `configs/glance-api.conf` | Controller | 이미지 서비스 설정 |
| `configs/placement.conf` | Controller | 리소스 배치 서비스 설정 |
| `configs/nova-controller.conf` | Controller | Nova API / Scheduler / Conductor 설정 |
| `configs/nova-compute.conf` | Compute | Nova Compute (KVM 드라이버) 설정 |

---

## 9월 작업 결과

- Controller / Compute / Block Storage 3노드 클러스터 구성 완료
- Keystone 토큰 발급 정상 확인 (`openstack token issue`)
- Glance cirros 이미지 등록 및 조회 확인
- Placement 리소스 인벤토리 등록 확인
- Nova Compute 노드 Cell 등록 및 서비스 목록 확인 (`openstack compute service list`)
- 전 노드 chrony 시간 동기화 확인

10월 작업: Neutron(OVS), Horizon, Cinder, Heat 설치 및 네트워크 트러블슈팅
