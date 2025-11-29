# Month 03 — DaaS 서비스 구현 및 검증 (2025.11)

## 작업 개요

9~10월에 구축한 OpenStack 클러스터 위에 실제 DaaS(Desktop as a Service) 서비스를 구현했다.

핵심 작업은 두 가지다.

첫째, Windows 10 / Ubuntu 골든 이미지를 직접 패키징하여 OpenStack Glance에 등록했다.
단순 OS 설치가 아니라 VirtIO 드라이버 통합, Sysprep 일반화, QCOW2 변환까지 포함하는 전 과정을 수행했다.

둘째, Kasm Workspaces를 WAS(Web Application Server)로 도입하여
사용자가 별도 클라이언트 설치 없이 웹 브라우저만으로 가상 데스크톱에 접속할 수 있는
Clientless DaaS 환경을 구현했다.

---

## 이달 작업 상세

### 1. DaaS 아키텍처 설계

3계층 VPC 구조로 설계했다.

**VPC 1 — On-Demand Control**

사용자 진입점. Kasm 웹 인터페이스를 통해 로그인 및 세션 관리.
Gateway를 통해 외부 인터넷과 내부 OpenStack API 계층을 연결.

**VPC 2 — OpenStack API**

Controller Node에서 Horizon / Nova / Keystone / Neutron / Cinder API를 제공.
Private Subnet으로 구성하여 외부 직접 접근 차단.
On-Demand Control VPC와만 통신하도록 설계.

**VPC 3 — DaaS Service**

실제 Windows / Linux 데스크톱 인스턴스가 실행되는 영역.
Kasm 스트리밍 서버가 각 VM에 RDP(3389 포트)로 연결하여 화면을 HTML5로 변환 후 전송.
User Data 스토리지에 학생별 실습 데이터 영구 보관.

**CPU 오버커밋 정책**

물리 CPU 코어(pCPU)와 가상 CPU(vCPU) 비율을 고려하여 오버커밋(Overcommit) 비율을 설정했다.
특정 인스턴스가 CPU를 독점하는 Noisy Neighbor 현상을 방지하기 위해
각 인스턴스 유형별 vCPU 개수와 처리 우선순위를 Flavor로 사전 정의하여 엄격하게 제한했다.

```
compute  노드: vCPU 12 used / 8 total → allocation ratio 3.0
controller 노드: vCPU 0 used / 8 total → allocation ratio 3.0
```

---

### 2. Golden Image 패키징

클라우드 환경에서 이미지 패키징은 단순 OS 설치가 아니다.
OpenStack과의 호환성 확보, 배포 속도 최적화를 위해
드라이버 통합 / 불필요한 서비스 제거 / 포맷 변환 등의 기술적 가공 과정이 필수다.

**대상 이미지**

- Windows 10 Pro (RDP 서버 기능 필수 → Home 버전 불가)
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

**이미지 생성 환경**

외부 네트워크와 격리된 KVM 환경에서 진행했다.
도구: `virt-manager` / `qemu-img`
CPU 가상화 확장 기능(Intel VT-x) 활성화로 빌드 속도 향상.

---

### 3. Windows 골든 이미지 패키징 상세

#### (1) 가상머신 생성 및 VirtIO 드라이버 준비

OpenStack은 QCOW2 포맷만 지원한다.
ISO / VDI / VMDK 등은 직접 등록 불가 → 변환 필수.

virt-manager에서 Windows 10 ISO와 VirtIO 드라이버 ISO를 동시에 마운트했다.

VirtIO를 사용해야 하는 이유:
- e1000e 같은 전가상화 모델 선택 시 OpenStack 이미지 배포 과정에서 네트워크 호환 문제 발생
- OpenStack은 이미지 배포 시 VM 하드웨어 구성을 동적으로 처리함
- 이미지 내부에 이전 NIC 설정이 남아 새 가상 네트워크를 인식하지 못하는 현상 발생
- VirtIO는 특정 하드웨어에 종속되지 않고 가상화 환경 자체에 최적화된 준가상화 드라이버

가상머신 설정:
- 디스크 인터페이스: VirtIO Block
- 네트워크 어댑터: VirtIO NIC
- 가상 CD-ROM 2개: Windows ISO + VirtIO 드라이버 ISO
- 최소 사양: 2 vCPU / 4GB RAM / 24GB Disk

#### (2) Windows 설치 중 VirtIO 디스크 드라이버 로드

Windows 설치 프로그램은 기본적으로 VirtIO 기반 가상 디스크를 인식하지 못한다.
설치 중 "드라이버 로드" 옵션에서 VirtIO ISO의 `RedHat VirtIO SCSI controller` 드라이버를 수동 로드해야 디스크가 인식된다.

#### (3) Windows 설치 후 설정

RDP 활성화

```
시스템 속성 → 원격 탭 → "이 컴퓨터에 대한 원격 연결 허용" 체크
```

VirtIO 전체 드라이버 설치 (네트워크 / 스토리지 / 기타 장치)
VirtIO ISO에 포함된 `virtio-win-gt-x64.msi` 실행하여 전체 드라이버 일괄 설치.

#### (4) Sysprep 이미지 일반화

일반화 없이 이미지를 배포하면 모든 VM이 동일한 호스트명과 SID(Security Identifier)를 가진다.
Windows SID 충돌 문제와 인스턴스 구분 불가 문제가 발생한다.

---

### 4. 트러블슈팅 — Windows Sysprep 일반화 실패

**문제 상황**

골든 이미지로 여러 VM을 배포했는데 모든 인스턴스가 동일한 호스트명을 가졌다.
이미지 패키징 과정에서 sysprep을 통한 일반화 단계를 건너뛰었기 때문이었다.
sysprep을 실행하려 했으나 Windows 10에서 일반 사용자 모드로는 권한 문제로 정상 작동하지 않았다.

**원인 분석**

일반화 없이 만든 이미지로 인스턴스를 생성하면
모든 VM이 원본 이미지의 호스트명 / SID / 사용자 설정을 그대로 복제한다.
Windows 10은 일반 사용자 모드에서 sysprep 실행 시 권한 문제가 발생한다.

**해결 과정**

1. 명령 프롬프트에서 감사 모드(Audit Mode)로 진입

```powershell
PS C:\Windows\System32\Sysprep> .\sysprep /audit /reboot
```

2. 감사 모드에서 관리자 권한으로 cloudbase-init 설치
   (OpenStack 메타데이터를 읽어 인스턴스별 호스트명 / 네트워크 / 사용자 계정 초기화)

3. Sysprep 실행으로 이미지 일반화 및 종료

```
C:\Windows\System32\Sysprep\sysprep.exe
→ "시스템 일반화" 체크 + "시스템 종료" 선택
```

4. VM 종료 상태에서 QCOW2 포맷으로 이미지 변환

```bash
qemu-img convert -f raw -O qcow2 win10.img win10-golden.qcow2
```

5. Glance에 골든 이미지로 등록

```bash
glance image-create --name "Windows-10-DaaS-Image" \
  --file win10-golden.qcow2 \
  --disk-format qcow2 --container-format bare \
  --visibility=public
```

**결과**

일반화된 이미지로 인스턴스를 생성하자 각 VM마다 고유한 호스트명과 SID가 자동 할당됐다.
cloudbase-init이 OpenStack 메타데이터를 읽어 인스턴스별로 다른 네트워크 설정 / 호스트명 / 사용자 계정을 초기화했다.

---

### 5. Kasm Workspaces 설치

기존 VNC 방식 대신 HTML5 기반 웹 스트리밍을 제공하는 Kasm Workspaces를 도입했다.
Docker 컨테이너 기반의 마이크로서비스 아키텍처로 구동된다.

OpenStack 인스턴스 위에 Ubuntu 서버를 생성하고, 그 위에 Kasm을 설치했다.

```bash
cd /tmp
curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_1.17.0.7f020d.tar.gz
tar -xf kasm_release_1.17.0.7f020d.tar.gz
sudo bash kasm_release/install.sh
```

설치 완료 후 실행 제어 디렉토리

```
/opt/kasm/bin/
├── start
├── stop
└── restart
```

Kasm 구동 컨테이너

| 컨테이너 | 역할 |
|---|---|
| kasm_api | API 서버 |
| kasm_manager | 세션 및 워크스페이스 관리 |
| kasm_proxy | 스트리밍 프록시 |

---

### 6. Kasm 관리자 설정

**사용자 계정 및 그룹 구성**

- Admin Role / User Role 분리하여 보안성 확보
- 사용자 그룹(Group)을 정의하여 역할 기반 접근 권한(RBAC) 차등 부여
- 계정별 접속 이력 확인 및 잠금(Lock) / 비활성화 처리 가능

**워크스페이스 생성**

연결 유형: RDP (Windows / Linux XRDP 모두 고해상도 그래픽 전송 가능)

OpenStack에서 구동 중인 Windows 및 Ubuntu 인스턴스를 각각 Server 유형의 워크스페이스로 등록.

---

### 7. OpenStack 인스턴스 ↔ Kasm 연동

Kasm 서버가 OpenStack 인스턴스의 Fixed IP 또는 Floating IP를 목적지로
3389(RDP) 포트로 터널링을 시도하는 구조다.

OpenStack 보안 그룹(Security Group)에서 Kasm 서버 IP로부터 유입되는 RDP 트래픽을 허용하도록 정책을 수정했다.

연동된 인스턴스

| 인스턴스 | IP | 상태 |
|---|---|---|
| ubuntu test | 192.168.0.189 | Running |
| windows test | 192.168.0.107 | Running |

---

### 8. DaaS 서비스 최종 검증

사용자 접속 흐름

```
웹 브라우저 → Kasm 로그인 → 워크스페이스 선택 → RDP 세션 수립
→ Kasm이 인스턴스 화면을 HTML5로 실시간 변환 → 사용자 화면에 스트리밍
```

보안 및 세션 관리

- 모든 접속 HTTPS 암호화 처리
- 등록된 사용자 계정만 접속 허용
- 브라우저 종료 또는 네트워크 단절 시 작업 화면 유지
- 일정 시간 입력 없을 시 자동 세션 종료 (서버 리소스 낭비 방지)

최종 검증 결과

웹 브라우저에서 Ubuntu(좌) / Windows 10(우) 인스턴스에 동시 접속 성공.
OpenStack Neutron에서 할당한 사설 IP(192.168.0.x 대역)가
가상 데스크톱 내부(`ifconfig` / `ipconfig`)에서도 정확히 매핑되어 동작하는 것을 확인했다.
별도 클라이언트(RDP, Putty 등) 없이 HTML5 웹 브라우저만으로
클라우드 내부 컴퓨팅 자원에 접근하는 Clientless DaaS 모델이 성공적으로 구현됐다.

---

## 설정 파일 목록

| 파일 | 설명 |
|---|---|
| `configs/kasm-workspace-windows.json` | Windows 인스턴스 워크스페이스 설정 |
| `configs/kasm-workspace-ubuntu.json` | Ubuntu 인스턴스 워크스페이스 설정 |
| `configs/glance-golden-images.sh` | 골든 이미지 Glance 등록 스크립트 |
| `configs/qcow2-convert.sh` | IMG → QCOW2 변환 명령어 |

---

## 11월 작업 결과

- Windows 10 / Ubuntu 골든 이미지 패키징 완료 (VirtIO 드라이버 통합 + Sysprep 일반화)
- Windows Sysprep 감사 모드 트러블슈팅 해결
- Kasm Workspaces 1.17.0 설치 및 Docker 컨테이너 정상 구동 확인
- OpenStack 인스턴스 2대(Windows / Ubuntu) Kasm 워크스페이스 연동 완료
- 웹 브라우저 기반 Clientless DaaS 서비스 최종 검증 완료
- Glance 이미지 목록에 7개 이미지 Active 상태 확인

---

## 프로젝트 최종 성과

- OpenStack Caracal 수동 설치를 통한 클라우드 인프라 구축 및 운영 경험
- 네트워크 트러블슈팅 2건 (ML2 드라이버 충돌, NIC 제어권 충돌) 직접 해결
- Windows / Linux 골든 이미지 패키징 및 클라우드 이미지 최적화 기법 학습
- 폐기 예정 서버 4대를 HCI 방식으로 재활용한 인프라 설계 경험
- Kasm Workspaces 기반 Clientless DaaS 서비스 구현 완료
