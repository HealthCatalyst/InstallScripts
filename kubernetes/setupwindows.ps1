Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
# https://github.com/OneGet/MicrosoftDockerProvider
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
# Uninstall-Package -ProviderName DockerMsftProvider -Name Docker -Verbose
# 17.06.01 is minimum
Install-Package -Name Docker -ProviderName DockerMsftProvider -Force -RequiredVersion 17.06.1-ee-2
Restart-Computer -Force

Write-Output "Checking if docker is working properly"
docker run microsoft/dotnet-samples:dotnetapp-nanoserver

# https://docs.microsoft.com/en-us/virtualization/windowscontainers/kubernetes/configuring-host-gateway-mode
# $url = "https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/windows/AddRoutes.ps1"
# wget $url -o AddRoutes.ps1

# https://kubernetes.io/docs/getting-started-guides/windows/

mkdir C:/k/

Write-Output "installing Windows tools to set up networking"

Invoke-WebRequest https://github.com/Microsoft/SDN/archive/master.zip -o master.zip
Expand-Archive master.zip -DestinationPath master
mv master/SDN-master/Kubernetes/windows/* C:/k/
rm -recurse -force master,master.zip

# get ip of master via ping
# get gateway from ipconfig
./AddRoutes.ps1 -MasterIp 10.239.0.4 -Gateway 10.239.0.1

Invoke-WebRequest "http://7-zip.org/a/7z1801-x64.exe" -o 7z1801-x64.exe
Start-Process .\7z1801-x64.exe

Write-Output "Downloading Windows Kube tools: kubectl, kubeadm"
Invoke-WebRequest https://dl.k8s.io/v1.9.2/kubernetes-node-windows-amd64.tar.gz -o kubernetes-node-windows-amd64.tar.gz
mv kubernetes-node-windows-amd64.tar.gz C:/k/

# download from our own location so we can use zip


# Expand-Archive kubernetes-node-windows-amd64.tar.gz -DestinationPath kubernetes-node-windows-amd64
# install 7-zip and extract

Write-Output "Creating the pause container"
docker pull microsoft/windowsservercore
docker tag microsoft/windowsservercore microsoft/windowsservercore:latest
cd C:/k/
docker build -t kubeletwin/pause .

docker images



# if using windows 1709
# docker pull microsoft/windowsservercore:1709
# docker tag microsoft/windowsservercore:1709 microsoft/windowsservercore:latest
# cd C:/k/
# docker build -t kubeletwin/pause .

# https://storage.googleapis.com/kubernetes-release/release/v1.9.1/kubernetes-node-windows-amd64.tar.gz
# copy to c:\k


Write-Output "TODO: Copy and create config here"

Write-Output "Setting environment variable to point to kube config"
$env:Path += ";C:\k"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::Machine)
$env:KUBECONFIG="C:\k\config"
[Environment]::SetEnvironmentVariable("KUBECONFIG", "C:\k\config", [EnvironmentVariableTarget]::User)
Get-ChildItem Env:

Write-Output "Checking to see if we can connect to kube master"
kubectl version

Get-NetAdapter

# https://github.com/MicrosoftDocs/Virtualization-Documentation/issues/529
# https://github.com/MicrosoftDocs/Virtualization-Documentation/tree/live/windows-server-container-tools/CleanupContainerHostNetworking
# net stop hns
# del C:\ProgramData\Microsoft\Windows\HNS\HNS.data
# net start hns

# Stop-service docker
# Get-ContainerNetwork | Remove-ContainerNetwork -Force
# Start-service docker

./start-kubelet.ps1
./start-kubeproxy.ps1

kubectl get nodes

kubectl get pods -n kube-system -o wide


# kubectl apply -f https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/WebServer.yaml
kubectl apply -f https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/testwindowsnanoserver.yml

kubectl get all -o wide

kubectl describe po -l app=win-nanoserver

kubectl apply -f https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/testwindowswebserver.yml

# https://github.com/MicrosoftDocs/Virtualization-Documentation/tree/master/windows-server-container-tools/Debug-ContainerHost
Invoke-WebRequest https://raw.githubusercontent.com/MicrosoftDocs/Virtualization-Documentation/master/windows-server-container-tools/Debug-ContainerHost/Debug-ContainerHost.ps1 -o Debug-ContainerHost.ps1

docker network create --driver host host

# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#44-joining-your-nodes
# kubectl drain <node name> --delete-local-data --force --ignore-daemonsets
# kubectl delete node <node name>