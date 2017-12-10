
#
# This script is meant for quick & easy install via:
#   curl -sSL https://healthcatalyst.github.io/InstallScripts/nlp/runondevmachine.sh | sh

echo "Version 1.01"

docker stack rm fabricnlp

# echo "sleeping for network to clean up"
# sleep 20s;

while docker network inspect -f "{{ .Name }}" fabricnlp_nlpnet &>/dev/null; do echo "."; sleep 1; done

docker secret rm MySQLPassword || echo ""
echo 'yourpassword' | docker secret create MySQLPassword -

docker secret rm MySQLRootPassword || echo ""
echo "new-password" |  docker secret create MySQLRootPassword -

docker secret rm ExternalHostName || echo ""
echo "localhost" | docker secret create ExternalHostName  -

docker secret inspect SmtpRelayPassword &>/dev/null
if [ $? -ne 0 ]; then
	echo "foo" | docker secret create SmtpRelayPassword  -
fi

export SHARED_DRIVE=c:/tmp/fabricnlp
mkdir -p ${SHARED_DRIVE}

export SHARED_DRIVE_LOGS=${SHARED_DRIVE}/fluentd
mkdir -p ${SHARED_DRIVE_LOGS}

export SHARED_DRIVE_SOLR=${SHARED_DRIVE}/solr
mkdir -p ${SHARED_DRIVE_SOLR}

export SHARED_DRIVE_MYSQL=${SHARED_DRIVE}/mysql
mkdir -p ${SHARED_DRIVE_MYSQL}

myreleaseversion="latest"

docker pull healthcatalyst/fabric.smtp.agent:$myreleaseversion
docker pull healthcatalyst/fabric.nlp.docker.mysql:$myreleaseversion
docker pull healthcatalyst/fabric.nlp.docker.solr:$myreleaseversion
docker pull healthcatalyst/fabric.nlp.docker.jobs:$myreleaseversion
docker pull healthcatalyst/fabric.nlp.docker.web:$myreleaseversion

# use docker stack deploy to start up all the services
stackfilename="nlp-stack.yml"

echo "running stack: $stackfilename"

# echo "https://healthcatalyst.github.io/InstallScripts/nlp/${stackfilename}"

# curl -sSL "https://healthcatalyst.github.io/InstallScripts/nlp/${stackfilename}" | docker stack deploy --compose-file - fabricnlp

docker stack deploy -c $stackfilename fabricnlp
