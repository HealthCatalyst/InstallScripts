Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name Docker -ProviderName DockerMsftProvider
Restart-Computer -Force

wget https://github.com/Microsoft/SDN/archive/master.zip -o master.zip
Expand-Archive master.zip -DestinationPath master
mkdir C:/k/
mv master/SDN-master/Kubernetes/windows/* C:/k/
rm -recurse -force master,master.zip

docker pull microsoft/windowsservercore:1709
docker tag microsoft/windowsservercore:1709 microsoft/windowsservercore:latest
cd C:/k/
docker build -t kubeletwin/pause .

https://storage.googleapis.com/kubernetes-release/release/v1.9.1/kubernetes-node-windows-amd64.tar.gz
# copy to c:\k

$env:Path += ";C:\k"

[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\k", [EnvironmentVariableTarget]::Machine)

kubectl version

$env:KUBECONFIG="C:\k\config"

[Environment]::SetEnvironmentVariable("KUBECONFIG", "C:\k\config", [EnvironmentVariableTarget]::User)

./start-kubelet.ps1 -ClusterCidr 192.168.0.0/16
./start-kubeproxy.ps1

kubectl apply -f https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/WebServer.yaml
