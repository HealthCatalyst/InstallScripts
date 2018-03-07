#!/bin/sh

# curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/ehr/installfabricehr.sh | sh

docker stop fabric.ehr
docker rm fabric.ehr
docker run -d -p 3000:3000 -e SQLServer=SQL2012VM --name fabric.ehr -t healthcatalyst/fabric.ehr 
