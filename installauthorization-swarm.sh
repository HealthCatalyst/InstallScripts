#!/bin/bash

set -e

authority=$1

echo "creating authnet network"
docker network create --driver overlay authnet

echo "creating authorization service"
docker service create --name authorization \
	--env IdentityServerConfidentialClientSettings__Authority=$authority \
	--replicas 1 \
	--network authnet \
	--network idnet \
	--network dbnet \
	healthcatalyst/fabric.authorization

echo "creating authorization nginx proxy"
docker service create --name authorizationproxy \
	--env HOST=authorization \
	--env REMOTEPORT=5004 \
	-p 5004:80 \
	--network authnet \
	healthcatalyst/fabric.docker.nginx
