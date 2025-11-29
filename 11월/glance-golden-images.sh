#!/bin/bash
# Glance 골든 이미지 등록 스크립트
# 변환 완료된 QCOW2 이미지를 OpenStack Glance에 등록
#
# 실행 전 openrc 환경변수 로드 필수
# source /root/openrc/admin-openrc

# Windows 10 DaaS 이미지 등록
glance image-create \
  --name "Windows-10-DaaS-Image" \
  --file win10-golden.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --visibility public

# Ubuntu 24.04 이미지 등록
glance image-create \
  --name "ubuntu-24.04-qcow2" \
  --file ubuntu-24.04-server.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --visibility public

# 등록된 이미지 목록 확인 (전부 Active 상태여야 함)
openstack image list
