#!/bin/bash

echo "creating dbnet network"
docker network create --driver overlay dbnet

echo "creating couchdb1 service"
docker service create --name  couchdb1 \
	--env NODENAME=couchdb1 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 15984:5984 \
	--network dbnet \
	healthcatalyst/fabric.docker.couchdb

echo "creating couchdb2 service"
docker service create --name couchdb2 \
	--env NODENAME=couchdb2 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 25984:5984 \
	--network dbnet \
	healthcatalyst/fabric.docker.couchdb

echo "creating couchdb3 service"
docker service create --name couchdb3 \
	--env NODENAME=couchdb3 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 35984:5984 \
	--network dbnet \
	healthcatalyst/fabric.docker.couchdb

echo "waiting for couchdb nodes to come up"
sleep 30

echo "configuring couch cluster"
./configure-couch-cluster.sh localhost 15984 25984 35984


echo "creating couch ha proxy service"
docker service create --name couchproxy \
	-p 5984:5984 \
	--network dbnet \
	healthcatalyst/fabric.docker.haproxy
