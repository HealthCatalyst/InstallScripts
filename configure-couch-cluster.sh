#!/bin/bash

set -e

couchnode=$1
couchport=$2
couchport2=$3
couchport3=$4

echo "enable cluster"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json' \
	--data-binary "{\"action\":\"enable_cluster\",\"username\":\"$COUCHDB_USER\",\"password\":\"$COUCHDB_PASSWORD\",\"bind_address\":\"0.0.0.0\",\"port\":5984}" --compressed

echo "enable cluster for couchd2"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json'  \
	--data-binary "{\"action\":\"enable_cluster\",\"username\":\"$COUCHDB_USER\",\"password\":\"$COUCHDB_PASSWORD\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"remote_node\":\"couchdb2\",\"remote_current_user\":\"$COUCHDB_USER\",\"remote_current_password\":\"$COUCHDB_PASSWORD\"}" --compressed

curl -sSL https://healthcatalyst.github.io/InstallScripts/wait-for-it.sh | sh /dev/stdin $couchnode:$couchport2 -t 300 -- echo "couchdb2 is up"

echo "add node couchdb2"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json' \
	--data-binary "{\"action\":\"add_node\",\"username\":\"$COUCHDB_USER\",\"password\":\"$COUCHDB_PASSWORD\",\"host\":\"couchdb2\",\"port\":5984}" --compressed

echo "enable cluster for couchdb3"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json' \
	--data-binary "{\"action\":\"enable_cluster\",\"username\":\"$COUCHDB_USER\",\"password\":\"$COUCHDB_PASSWORD\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"remote_node\":\"couchdb3\",\"remote_current_user\":\"$COUCHDB_USER\",\"remote_current_password\":\"$COUCHDB_PASSWORD\"}" --compressed

curl -sSL https://healthcatalyst.github.io/InstallScripts/wait-for-it.sh | sh /dev/stdin $couchnode:$couchport3 -t 300 -- echo "couchdb3 is up"

echo "add node for couchdb3"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json' \
	--data-binary "{\"action\":\"add_node\",\"username\":\"$COUCHDB_USER\",\"password\":\"$COUCHDB_PASSWORD\",\"host\":\"couchdb3\",\"port\":5984}" --compressed

echo "finish cluster"
curl "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$couchnode:$couchport/_cluster_setup" -H 'Content-Type: application/json' -H 'Accept: application/json' \
	--data-binary "{\"action\":\"finish_cluster\"}" --compressed

