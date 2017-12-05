
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/1/realtime/runondevmachine.sh | sh

myreleaseversion="1"

echo "script version: 1.0.0"

docker stack rm fabricrealtime &>/dev/null

 echo "waiting until network is removed"

while docker network inspect -f "{{ .Name }}" fabricrealtime_realtimenet &>/dev/null; do 
	echo "."; 
	sleep 1; 
done

docker secret rm CertPassword || echo ""
echo "roboconf2" |  docker secret create CertPassword -

docker secret rm RabbitMqMgmtUiPassword || echo ""
echo 'roboconf2' | docker secret create RabbitMqMgmtUiPassword -

docker secret rm CertHostName || echo ""
echo "localrealtime" |  docker secret create CertHostName -


connectToSqlServer=""
while true; do
    read -e -p "Do you wish to use an external Microsoft SQL Server for interface engine logs?" yn < /dev/tty
    case $yn in
        [Yy]* ) connectToSqlServer="yes"; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [[ ! -z "$connectToSqlServer" ]]
then
    echo "Setting username to $USERNAME"
    docker secret rm SqlServerUserName || echo ""
    echo $USERNAME | docker secret create SqlServerUserName -

    read -p "Please type in password for $USERNAME:" -e sqlserverpassword < /dev/tty
    docker secret rm SqlServerPassword || echo ""
    echo $sqlserverpassword | docker secret create SqlServerPassword -

    echo "Using domain $USERDNSDOMAIN"
    docker secret rm SqlServerDomain || echo ""
    echo $USERDNSDOMAIN | docker secret create SqlServerDomain -

    read -p "Please type in Windows Active Directory URL to use to connect to SQL Server (e.g., hcsad1):" -e sqlserveradurl < /dev/tty
    docker secret rm SqlServerADUrl || echo ""
    echo $sqlserveradurl | docker secret create SqlServerADUrl -
    # HCSAD1

    read -p "Please type in SQL Server to connect to (e.g., $COMPUTERNAME):" -e sqlserverserver < /dev/tty
    docker secret rm SqlServerName || echo ""
    echo $sqlserverserver | docker secret create SqlServerName -
    # COMPUTERNAME

    read -p "Please type in Database Name to use in SQL Server (e.g., MyRealtimeDb):" -e sqlserverdatabase < /dev/tty
    docker secret rm sqlserverdatabase || echo ""
    echo $sqlserverdatabase | docker secret create SqlServerDatabase -
else

    docker secret rm MySQLPassword || echo ""
    echo 'roboconf2' | docker secret create MySQLPassword -

    docker secret rm MySQLRootPassword || echo ""
    echo "roboconf2" |  docker secret create MySQLRootPassword -
fi


export DISABLE_SSL="true"
export SHARED_DRIVE=c:/tmp/fabricrealtime
mkdir -p ${SHARED_DRIVE}

export SHARED_DRIVE_CERTS=c:/tmp/certs
mkdir -p ${SHARED_DRIVE}/certs

export SHARED_DRIVE_RABBITMQ=c:/tmp/rabbitmq
mkdir -p ${SHARED_DRIVE}/rabbitmq

export SHARED_DRIVE_MYSQL=c:/tmp/mysql
mkdir -p ${SHARED_DRIVE}/mysql

export SHARED_DRIVE_LOGS=c:/tmp/fluentd
mkdir -p ${SHARED_DRIVE}/fluentd

# export SQLSERVER_USER=imran.qureshi
# export SQLSERVER_DOMAIN=hqcatalyst.local
# export SQLSERVER_AD_URL=hcsad1
# export SQLSERVER_SERVER=hc2034
# export SQLSERVER_DATABASE=MyRealtimeDb

# docker stack deploy -c realtime-stack.yml fabricrealtime

# use docker stack deploy to start up all the services
stackfilename="realtime-stack.yml"
if [[ ! -z "$connectToSqlServer" ]]
then
	stackfilename="realtime-stack-sqlserver.yml"
fi

# make sure we can pull an image
docker pull healthcatalyst/fabric.docker.interfaceengine:$myreleaseversion
docker pull healthcatalyst/fabric.certificateserver:$myreleaseversion
docker pull healthcatalyst/fabric.realtime.rabbitmq:$myreleaseversion
docker pull healthcatalyst/fabric.realtime.mysql:$myreleaseversion

echo "running stack: $stackfilename"

echo "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/$myreleaseversion/realtime/${stackfilename}"

curl -sSL "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/$myreleaseversion/realtime/${stackfilename}" | docker stack deploy --compose-file - fabricrealtime