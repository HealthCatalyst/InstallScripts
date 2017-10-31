
#
# This script is meant for quick & easy install via:
#   curl -sSL https://healthcatalyst.github.io/InstallScripts/realtime/runondevmachine.sh | sh


docker stack rm fabricrealtime

sleep 10s;

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
    read -p "Please type in username of Windows Service Account to use to connect to SQL Server (e.g., imran.qureshi):" -e sqlserverusername < /dev/tty
    docker secret rm SqlServerUserName || echo ""
    echo $sqlserverusername | docker secret create SqlServerUserName -

    read -p "Please type in password for Windows Service Account to use to connect to SQL Server:" -e sqlserverpassword < /dev/tty
    docker secret rm SqlServerPassword || echo ""
    echo $sqlserverpassword | docker secret create SqlServerPassword -

    read -p "Please type in Windows domain to use to connect to SQL Server (e.g., hqcatalyst.local):" -e sqlserverdomain < /dev/tty
    docker secret rm SqlServerDomain || echo ""
    echo $sqlserverdomain | docker secret create SqlServerDomain -

    read -p "Please type in Windows Active Directory URL to use to connect to SQL Server (e.g., hcsad1):" -e sqlserveradurl < /dev/tty
    docker secret rm SqlServerADUrl || echo ""
    echo $sqlserveradurl | docker secret create SqlServerADUrl -

    read -p "Please type in SQL Server to connect to (e.g., hc2034):" -e sqlserverserver < /dev/tty
    docker secret rm SqlServerName || echo ""
    echo $sqlserverserver | docker secret create SqlServerName -

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
export SHARED_DRIVE=c:/tmp
export SHARED_DRIVE_CERTS=c:/tmp/certs
export SHARED_DRIVE_RABBITMQ=c:/tmp/rabbitmq
export SHARED_DRIVE_MYSQL=c:/tmp/mysql

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

curl -sSL "https://healthcatalyst.github.io/InstallScripts/realtime/${stackfilename}?rand=$RANDOMNUMBER" | docker stack deploy --compose-file - fabricrealtime