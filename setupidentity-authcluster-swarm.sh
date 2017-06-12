#!/bin/bash

set -e

if [ $# -ne 2 ]; then
	echo "You must specify CouchDB User as first argument and CouchDB Password as second argument"
else
	export COUCHDB_USER=$1
	export COUCHDB_PASSWORD=$2
	./installcouchdbcluster-swarm.sh
	./installidentity-swarm.sh http://couchproxy:5984
	./installauthorization-swarm.sh http://identity:5001
fi

