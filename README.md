# OpenStack 기반 DaaS 서비스 구축

참여 인원 : 3명 
수행 기간: 2025.09 ~ 2025.12

## **✨ 프로젝트 개요**

본 프로젝트는 폐기 예정이던 서버 4대를 HCI 방식으로 통합하여 OpenStack 클러스터를 구축하고, 기존에 CLI/API만 제공하던 클라우드 환경에 GUI 기반의 DaaS 서비스를 추가한 것입니다. 

학생들은 Kasm 웹 브라우저에 로그인하면 미리 연결된 Windows/Linux 데스크톱을 즉시 실행할 수 있으며, 학교와 집 어디서든 웹 브라우저만으로 동일한 환경에서 실습할 수 있습니다.

<img width="1146" height="713" alt="image" src="https://github.com/user-attachments/assets/d5ccc47e-1f56-4c72-95f3-a7dad29539a3" />
## ✏️ **아키텍처**

[OpenStack 기반 DaaS 서비스 시스템 아키텍처]

시스템은 3개 VPC로 구성되어 있습니다. 
[On-Demand Control] 
Kasm 웹 인터페이스를 통해 사용자 진입점을 제공

[OpenStack API] 
Controller Node(Horizon, Nova, Keystone), Compute Node, BlockStorage Node로 가상화 인프라를 관리 

[DaaS Service] 
VM Pool을 통해 최종 Windows/Linux 데스크톱 환경을 제공합니다.

핵심은 기존 OpenStack이 CLI/API를 통한 기술적 접근만 제공했던 것과 달리, 학생들이 웹 브라우저에서 로그인 후 클릭 한 번으로 자신의 데스크톱을 실행할 수 있다는 점입니다. 복잡한 인스턴스 생성, 네트워크 설정, 볼륨 연결 과정을 완전히 추상화하여 일반 사용자도 쉽게 접근할 수 있게 만들었습니다. Nova Compute가 Hypervisor를 관리하며, Neutron Agent가 가상 네트워크 구성을 담당합니다.


## 🙋 본인이 수행한 역할

- OpenStack  Caracal 인프라 구축 및 HCI 클러스터 구성
- Daas 시스템 아키텍처 설계
- VirtIO 기반 골든 이미지 패키징 및 성능 최적화
- 최종발표
## 📝상세내용

- OpenStack Caracal 클러스터 구축

해당 프로젝트는 폐기 예정 서버 4대를 OpenStack Caracal을 설치 및 구성했습니다. 컨트롤러 노드의 사양을 변경하여 스토리지 기능을 함께 수행하도록 HCI 방식으로 통합하여 설계하였습니다.

- 물리 인프라 구성
    
    <img width="610" height="406" alt="image" src="https://github.com/user-attachments/assets/2e5a75a0-5318-45f1-9d57-17cb9a040388" />

    
    - **물리 인프라 및 컴포넌트 구성**: 폐기 예정 서버 4대를 다음과 같이 구성했습니다.
        - **Controller Node (1대)**:
            - Keystone(인증 및 권한)
            - Glance(이미지 관리)
            - Nova-API(컴퓨트 제어)
            - Neutron-Server(네트워크 관리)
            - Cinder-API(스토리지 제어)
            - Horizon(웹 대시보드)
            - Nova-Compute
        - **Compute Node (2대)**:
            - Nova-Compute(가상 머신 실행 환경)
        - **BlockStorage Node (1대)**:
            - Cinder-Volume(블록 스토리지 제공)
        
        컨트롤러 노드의 사양을 변경하여 컴퓨트 기능을 통합함으로써 제한된 하드웨어로 최대 효율을 추출했습니다. Ubuntu 22.04 Live Server 기반 OpenStack Caracal을 수동 설치(manual installation) 방식으로 구성했습니다.
      
        
- **3-Tier VPC 아키텍처 설계**:
- **[On-Demand Control]** : Kasm 웹 애플리케이션 서버를 배치하고, 사용자 인증 및 세션 관리를 담당합니다. 학생들은 이 계층을 통해 로그인하며, 관리자가 사전에 연결한 Windows/Linux 인스턴스 목록을 확인할 수 있습니다. Gateway를 통해 외부 인터넷과 내부 OpenStack API 계층을 연결합니다.
- 
- **[OpenStack API]** : Controller Node에서 Horizon(웹 대시보드), Nova(컴퓨트), Keystone(인증), Neutron(네트워크), Cinder(스토리지) API를 제공하며, Compute Node 2대와 BlockStorage Node 1대를 관리합니다. Private Subnet으로 구성하여 외부 접근을 차단하고, On-Demand Control VPC와만 통신하도록 설계했습니다.
- 
- **[DaaS Service]** : VM Pool을 통해 실제 Windows/Linux 데스크톱 인스턴스를 실행하는 계층입니다. Kasm 스트리밍 서버가 각 VM에 연결되어 웹 브라우저로 화면을 전송하며, RDP Server를 통해 원격 데스크톱 프로토콜을 처리합니다. User Data 저장소는 학생별 실습 데이터를 영구 보관합니다.
            
이 구조는 사용자 접근 계층, 인프라 관리 계층, 서비스 제공 계층을 명확히 분리하여 보안성과 확장성을 확보했습니다.
            
- **이미지 패키징 작업**
            
            
  <img width="1007" height="702" alt="image" src="https://github.com/user-attachments/assets/7063cfd9-c56c-4f80-bc93-dc30a62fb2f1" />

            
  <img width="995" height="711" alt="image" src="https://github.com/user-attachments/assets/3020da60-3438-4d1c-966e-ef2898eed049" />

            
**골든 이미지 패키징 및 클라우드 최적화**: 
Windows 10와 Linux(Ubuntu 22.04, CentOS 7) 골든 이미지를 virt-manager를 통해 구성했습니다.
  
VM 생성 시 디스크 인터페이스를 VirtIO Block, 네트워크 어댑터를 VirtIO NIC로 사전 설정한 후 부팅했습니다. Windows 설치 과정에서 VirtIO 드라이버 ISO를 마운트하여 가상 디스크와 네트워크를 인식시켰으며, 설치 완료 후 cloudbase-init과 sysprep을 통해 사용자별 초기 설정(이름, 비밀번호)이 가능하도록 이미지를 일반화했습니다.
최종적으로 qcow2 포맷으로 변환하여 클라우드 환경에 최적화된 이미지를 생성했고, C/C++ 컴파일러, 개발 라이브러리, 네트워크 분석 도구 등 학교 실습 도구를 사전 포함했습니다.

