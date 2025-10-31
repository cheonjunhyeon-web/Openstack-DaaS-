# Month 02 — OpenStack 컴포넌트 완성 및 트러블슈팅 (2025.10)

## 작업 개요

9월에 구축한 기초 인프라(Keystone / Glance / Placement / Nova) 위에
네트워킹(Neutron), 대시보드(Horizon), 블록 스토리지(Cinder), 오케스트레이션(Heat)을 추가 설치했다.

이달의 핵심은 **Neutron OVS 구성 과정에서 발생한 네트워크 장애 2건**이다.
겉보기엔 모든 설정이 정상이었으나 인스턴스 외부 통신이 불가했고,
원인을 찾는 과정에서 OpenStack ML2 플러그인 구조와 OVS 브릿지 동작 방식을 깊이 이해하게 됐다.

---

## 이달 작업 상세

### 1. Neutron (네트워킹 서비스)

OpenStack 환경에서 SDN(Software Defined Networking) 기반의 가상 네트워크 인프라를 제공하는 컴포넌트.
사용자가 가상 네트워크 / 서브넷 / 라우터를 논리적으로 구성할 수 있도록 지원한다.

**Caracal 버전 표준 드라이버: Open vSwitch(OVS)**

ML2(Modular Layer 2) 플러그인 구조를 채택하여 OVS와 연동.
네트워크 타입은 flat / vlan / vxlan을 지원하며, 테넌트 네트워크는 vxlan으로 구성했다.

**Controller 노드 설치 컴포넌트**

- `neutron-server` : API 서버
- `neutron-plugin-ml2` : ML2 플러그인
- `neutron-openvswitch-agent` : OVS 에이전트
- `neutron-l3-agent` : L3 라우팅
- `neutron-dhcp-agent` : DHCP 서비스
- `neutron-metadata-agent` : 인스턴스 메타데이터 제공

**Compute 노드 설치 컴포넌트**

- `neutron-openvswitch-agent` : OVS 에이전트

**OVS 브릿지 구성**

```bash
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eno1
```

물리 NIC(eno1)을 br-provider 브릿지에 연결하고,
IP 주소를 eno1에서 br-provider로 이전했다.

**ml2_conf.ini 핵심 설정**

```
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch
extension_drivers = port_security
vni_ranges = 1:1000
bridge_mappings = provider:br-provider
tunnel_types = vxlan
l2_population = true
```

검증 (5개 에이전트 전부 UP 확인 필수)

```bash
openstack network agent list
```

---

### 2. 트러블슈팅 1 — Linux Bridge / OVS 충돌

**문제 상황**

Neutron 설치 완료 후 인스턴스 생성과 IP 발급은 정상이었으나,
외부 통신 테스트에서 ping이 나가지 않았다.
`openstack network agent list`에서 모든 에이전트가 활성화된 상태였음에도 통신 불가.

**원인 분석**

팀원과 설정 파일을 크로스체킹하던 중 문제를 발견했다.
초기에 Linux Bridge로 Neutron을 구성했다가 Caracal 버전이 OVS를 표준으로 사용한다는 점을 인식하고 OVS를 추가 설치했다.
그러나 `/etc/neutron/plugins/ml2/ml2_conf.ini`에서 두 mechanism driver가 동시에 활성화되어 있었다.

```
# 문제가 된 설정
mechanism_drivers = linuxbridge,openvswitch
```

OpenStack ML2 플러그인은 한 번에 하나의 mechanism driver만 사용해야 한다.
Linux Bridge와 OVS가 함께 작동하면서 네트워크 패킷 라우팅이 충돌했다.

**해결 과정**

1. `ml2_conf.ini`에서 mechanism_drivers를 `openvswitch`로만 명시

```
mechanism_drivers = openvswitch
```

2. `ovs-vsctl add-br br-provider` 로 Provider 네트워크용 OVS 브릿지 생성
3. `ovs-vsctl add-port br-provider eno1` 로 물리 인터페이스를 브릿지에 연결
4. `bridge_mappings = provider:br-provider` 로 수정
5. Netplan 설정을 통해 IP 주소를 물리 NIC에서 br-provider 브릿지로 이전

**결과**

인스턴스에서 외부로 ping이 정상적으로 나갔고,
`openstack network agent list`에서 모든 OVS agent가 활성 상태로 표시됐다.
이 경험을 통해 OpenStack ML2 플러그인의 구조와 mechanism driver 간 충돌 메커니즘,
OVS 브릿지 설정의 중요성을 깊이 이해하게 됐다.

---

### 3. 트러블슈팅 2 — OVS와 물리 NIC 제어권 충돌

**문제 상황**

첫 번째 트러블슈팅 해결 후 인스턴스 외부 통신은 정상화됐으나,
관리망(10.0.0.x 대역) 내부 통신에 문제가 발생했다.
Controller 노드와 Compute 노드 간 기본 ping은 성공했지만,
RabbitMQ(포트 5672)와 Keystone(포트 5000) 같은 OpenStack 핵심 서비스로의 연결이 실패했다.

**원인 분석**

관리망을 담당하는 물리 NIC(`enx68e4...`)에 Netplan으로 IP 주소(10.0.0.10)를 직접 할당한 상태에서,
동시에 OVS 브릿지의 포트로도 추가되어 있었다.

OVS 원칙상 브릿지 포트로 사용되는 물리 NIC에는 IP를 직접 할당하면 안 되며,
IP는 브릿지 인터페이스 자체에 할당되어야 한다.
이 충돌로 인해 커널과 OVS가 동시에 NIC 제어권을 가지려 하면서 내부 통신이 막혔다.

**해결 과정**

1. `sudo ovs-vsctl del-port br-provider enx68e4...` 로 관리망 NIC를 OVS 브릿지에서 제거
2. `sudo ip link set dev enx68e4... down` 후 `up` 으로 NIC 상태 초기화 (OVS 잔여 설정 완전 제거)
3. `sudo netplan apply` 로 설정 재적용하여 IP 주소와 라우팅 확정

**결과**

NIC를 OVS 포트에서 분리하고 커널에 제어권을 넘기자,
Netplan에 설정된 IP로 정상 통신이 가능해졌다.
Compute 노드에서 Controller 노드의 모든 서비스 포트로 연결이 성공했고,
OpenStack 클러스터 내부 통신이 안정화됐다.

---

### 4. Horizon (웹 대시보드)

OpenStack 인프라를 GUI로 제어하고 모니터링할 수 있는 공식 웹 인터페이스.
Django 기반으로 동작하며, 내부적으로는 Nova / Neutron / Cinder 등의 REST API를 호출한다.

- Apache2 기반으로 서비스
- Memcached 세션 백엔드 연동
- Keystone v3 / 멀티도메인 지원 활성화
- 시간대: Asia/Seoul

접속 주소: `http://192.168.0.10/horizon`

---

### 5. Cinder (블록 스토리지 서비스)

인스턴스에 영구적인 블록 스토리지 볼륨을 제공하는 서비스.
인스턴스가 종료되어도 데이터가 유지되는 영구 스토리지(Persistent Storage)를 구현한다.

**Controller 노드**: `cinder-api` / `cinder-scheduler` 설치

**Block Storage 노드**: `cinder-volume` 설치 + LVM 백엔드 구성

LVM 볼륨 그룹 생성

```bash
pvcreate /dev/vdb
vgcreate cinder-volumes /dev/vdb
```

iSCSI 프로토콜을 통해 인스턴스에 볼륨을 마운트하는 구조.
스냅샷 및 볼륨 복제 기능을 통해 골든 이미지 기반 부팅 볼륨 생성에도 활용했다.

검증

```bash
openstack volume service list
```

---

### 6. Heat (오케스트레이션 서비스)

텍스트 기반 템플릿(HOT: Heat Orchestration Template)으로
VM / 네트워크 / 스토리지를 한 번에 자동 배포하는 IaC(Infrastructure as Code) 서비스.

각 리소스 간 의존성을 자동으로 분석하여 생성 및 삭제 순서를 제어한다.

검증

```bash
openstack orchestration service list
```

---

### 7. Flavor 및 볼륨 운용

**Flavor (가상 하드웨어 사양 템플릿)**

인스턴스 생성 시 할당되는 vCPU / RAM / Disk 조합을 사전 정의한 템플릿.
Nova 스케줄러는 Flavor 요구사항을 기반으로 최적 물리 노드를 탐색한다.

```bash
openstack flavor create --vcpus 2 --ram 4096 --disk 20 <flavor-name>
```

**볼륨 생성**

```bash
openstack volume create --size 10 <볼륨이름>
openstack volume create --image <이미지이름> --size 20 --bootable <볼륨이름>
```

---

## 설정 파일 목록

| 파일 | 노드 | 설명 |
|---|---|---|
| `configs/neutron.conf` | Controller | Neutron 핵심 설정 |
| `configs/ml2_conf.ini` | Controller | ML2 플러그인 설정 (mechanism driver: openvswitch) |
| `configs/openvswitch_agent-controller.ini` | Controller | OVS 에이전트 설정 |
| `configs/openvswitch_agent-compute.ini` | Compute | OVS 에이전트 설정 |
| `configs/l3_agent.ini` | Controller | L3 라우팅 에이전트 설정 |
| `configs/dhcp_agent.ini` | Controller | DHCP 에이전트 설정 |
| `configs/metadata_agent.ini` | Controller | 메타데이터 에이전트 설정 |
| `configs/horizon_local_settings.py` | Controller | Horizon 대시보드 설정 |
| `configs/cinder-controller.conf` | Controller | Cinder API / Scheduler 설정 |
| `configs/cinder-volume.conf` | Block Storage | Cinder Volume / LVM 백엔드 설정 |

---

## 10월 작업 결과

- Neutron OVS 구성 완료 및 네트워크 에이전트 5개 전부 UP 확인
- Linux Bridge / OVS 충돌 트러블슈팅 해결
- NIC 제어권 충돌 트러블슈팅 해결
- Horizon 대시보드 접속 확인 (`http://192.168.0.10/horizon`)
- Cinder LVM 볼륨 서비스 정상 확인
- Heat 오케스트레이션 서비스 정상 확인
- Flavor 생성 및 볼륨 생성 테스트 완료

11월 작업: Golden Image 패키징, Kasm Workspaces 설치, DaaS 서비스 구현 및 검증
