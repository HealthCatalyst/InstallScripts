Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name Docker -ProviderName DockerMsftProvider -Force
Restart-Computer -Force

docker run microsoft/dotnet-samples:dotnetapp-nanoserver

# https://docs.microsoft.com/en-us/virtualization/windowscontainers/kubernetes/configuring-host-gateway-mode
$url = "https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/windows/AddRoutes.ps1"
wget $url -o AddRoutes.ps1
./AddRoutes.ps1 -MasterIp 10.1.2.3 -Gateway 10.1.3.1

mkdir C:/k/
Invoke-WebRequest https://github.com/Microsoft/SDN/archive/master.zip -o master.zip
Expand-Archive master.zip -DestinationPath master
mv master/SDN-master/Kubernetes/windows/* C:/k/
rm -recurse -force master,master.zip

Invoke-WebRequest "http://7-zip.org/a/7z1801-x64.exe" -o 7z1801-x64.exe
Start-Process .\7z1801-x64.exe

Invoke-WebRequest https://dl.k8s.io/v1.9.2/kubernetes-node-windows-amd64.tar.gz -o kubernetes-node-windows-amd64.tar.gz
mv kubernetes-node-windows-amd64.tar.gz C:/k/

Expand-Archive kubernetes-node-windows-amd64.tar.gz -DestinationPath kubernetes-node-windows-amd64
# install 7-zip and extract

docker pull microsoft/windowsservercore
docker tag microsoft/windowsservercore microsoft/windowsservercore:latest
cd C:/k/
docker build -t kubeletwin/pause .

# docker pull microsoft/windowsservercore:1709
# docker tag microsoft/windowsservercore:1709 microsoft/windowsservercore:latest
# cd C:/k/
# docker build -t kubeletwin/pause .

# https://storage.googleapis.com/kubernetes-release/release/v1.9.1/kubernetes-node-windows-amd64.tar.gz
# copy to c:\k

$env:Path += ";C:\k"

[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\k", [EnvironmentVariableTarget]::Machine)

$env:KUBECONFIG="C:\k\config"

[Environment]::SetEnvironmentVariable("KUBECONFIG", "C:\k\config", [EnvironmentVariableTarget]::User)
Get-ChildItem Env:

kubectl version

# https://github.com/MicrosoftDocs/Virtualization-Documentation/issues/529
# https://github.com/MicrosoftDocs/Virtualization-Documentation/tree/live/windows-server-container-tools/CleanupContainerHostNetworking
net stop hns
del C:\ProgramData\Microsoft\Windows\HNS\HNS.data
net start hns

Stop-service docker
Get-ContainerNetwork | Remove-ContainerNetwork -Force
Start-service docker

./start-kubelet.ps1 -ClusterCidr 192.168.0.0/16
./start-kubeproxy.ps1

kubectl apply -f https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/WebServer.yaml
