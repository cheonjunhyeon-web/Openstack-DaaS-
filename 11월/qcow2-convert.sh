#!/bin/bash
# IMG → QCOW2 변환 스크립트
# OpenStack Glance는 QCOW2 포맷만 지원
# ISO / VDI / VMDK 등은 직접 등록 불가 → 변환 필수
#
# 사용법: ./qcow2-convert.sh <원본파일.img> <출력파일.qcow2>
#
# 전제조건:
# - virt-manager에서 VM 생성 시 디스크 포맷을 raw(img)로 설정
# - Sysprep 일반화 완료 후 VM 종료 상태에서 변환할 것
# - VM이 실행 중인 상태에서 변환하면 이미지 손상 위험

INPUT=$1
OUTPUT=$2

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
  echo "사용법: ./qcow2-convert.sh <원본.img> <출력.qcow2>"
  exit 1
fi

echo "변환 시작: $INPUT → $OUTPUT"
qemu-img convert -f raw -O qcow2 "$INPUT" "$OUTPUT"
echo "변환 완료"

# 변환된 이미지 정보 확인
qemu-img info "$OUTPUT"
