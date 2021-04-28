#!/bin/bash

set -x

IP=$(ip route show |grep -o src.* |cut -f2 -d" ")
# kubernetes sets routes differently -- so we will discover our IP differently
if [[ ${IP} == "" ]]; then
  IP=$(hostname -i)
fi

SUBNET=$(echo ${IP} | cut -f1 -d.)
NETWORK=$(echo ${IP} | cut -f3 -d.)

case "${SUBNET}" in
    10)
        orchestrator=ecs
        ;;
    192)
        orchestrator=kubernetes
        ;;
    *)
        orchestrator=unknown
        ;;
esac

if [[ "${orchestrator}" == 'ecs' ]]; then
    case "${NETWORK}" in
      100)
        zone=a
        color=Crimson
        ;;
      101)
        zone=b
        color=CornflowerBlue
        ;;
      102)
        zone=c
        color=LightGreen
        ;;
      *)
        zone=unknown
        color=Yellow
        ;;
    esac
fi

if [[ "${orchestrator}" == 'kubernetes' ]]; then
    if ((0<=${NETWORK} && ${NETWORK}<32))
        then
            zone=a
    elif ((32<=${NETWORK} && ${NETWORK}<64))
        then
            zone=b
    elif ((64<=${NETWORK} && ${NETWORK}<96))
        then
            zone=c
    elif ((96<=${NETWORK} && ${NETWORK}<128))
        then
            zone=a
    elif ((128<=${NETWORK} && ${NETWORK}<160))
        then
            zone=b
    elif ((160<=${NETWORK}))
        then
            zone=c
    else
        zone=unknown
    fi
fi

if [[ ${orchestrator} == 'unknown' ]]; then
  zone=$(curl -m2 -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.availabilityZone' | grep -o .$)
fi

# Am I on ec2 instances?
if [[ ${zone} == "unknown" ]]; then
  zone=$(curl -m2 -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.availabilityZone' | grep -o .$)
fi

# Still no luck? Perhaps we're running fargate!
if [[ -z ${zone} ]]; then
  ip_addr=$(curl -m2 -s ${ECS_CONTAINER_METADATA_URI} | jq '.Networks[].IPv4Addresses[]')
  declare -a subnets=( $(aws ec2 describe-subnets | jq .Subnets[].CidrBlock| sed ':a;N;$!ba;s/\n/ /g') )

  for sub in "${subnets[@]}"; do
    if $(ruby -e "puts(IPAddr.new($sub.to_s).include? $ip_addr.to_s)") == 'true'; then
      zone=$(aws ec2 describe-subnets | jq -r ".Subnets[] | select(.CidrBlock==$sub) | .AvailabilityZone" | grep -o .$)
    fi
  done
fi

export CODE_HASH="$(cat code_hash.txt)"
export AZ="${IP} in AZ-${zone}"

# exec bundle exec thin start
RAILS_ENV=production rake assets:precompile
exec rails s -e production -b 0.0.0.0
