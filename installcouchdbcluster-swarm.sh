#!/bin/bash

nodelist=$(docker node ls -q)
echo "Node list is = $nodelist"
IFS=' ' read -r -a nodes <<< $nodelist
numbernodes=${#nodes[@]}
node1=${nodes[0]}
node2=${nodes[0]}
node3=${nodes[0]}

if [ $numbernodes -eq 2 ]; then
	node2=${nodes[1]}
	node3=${nodes[1]}
elif [ $numbernodes -ge 3 ]; then
	node2=${nodes[1]}
	node3=${nodes[2]}
fi

echo "Node1 id = $node1"
echo "Node2 id = $node2"
echo "Node3 id = $node3"

echo "creating dbnet network"
docker network create --driver overlay dbnet

cat > CouchDbSettings__Username << EOF
$COUCHDB_USER
EOF

cat > CouchDbSettings__Password << EOF
$COUCHDB_PASSWORD
EOF

docker secret create CouchDbSettings__Username CouchDbSettings__Username
docker secret create CouchDbSettings__Password CouchDbSettings__Password

rm CouchDbSettings__Username
rm CouchDbSettings__Password

echo "creating couchdb1 service"
docker service create --name  couchdb1 \
	--env NODENAME=couchdb1 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 15984:5984 \
	--network dbnet \
	--mount type=volume,source=db1-data,destination=//opt/couchdb/data \
	--constraint "node.id == $node1" \
	healthcatalyst/fabric.docker.couchdb

echo "creating couchdb2 service"
docker service create --name couchdb2 \
	--env NODENAME=couchdb2 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 25984:5984 \
	--network dbnet \
	--mount type=volume,source=db2-data,destination=//opt/couchdb/data \
	--constraint "node.id == $node2" \
	healthcatalyst/fabric.docker.couchdb

echo "creating couchdb3 service"
docker service create --name couchdb3 \
	--env NODENAME=couchdb3 \
	--env COUCHDB_USER=$COUCHDB_USER \
	--env COUCHDB_PASSWORD=$COUCHDB_PASSWORD \
	-p 35984:5984 \
	--network dbnet \
	--mount type=volume,source=db3-data,destination=//opt/couchdb/data \
	--constraint "node.id == $node3" \
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
