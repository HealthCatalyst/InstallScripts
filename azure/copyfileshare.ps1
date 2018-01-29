

# destination storage account name
$destResourceGroup = "Imran1"
$destAccountName = "imranstoragetest"
$destAccountKey = az storage account keys list -g $destResourceGroup -n $destAccountName --query "[0].value" -o tsv
$destConnectionString = az storage account show-connection-string -n $destAccountName -g $destResourceGroup -o tsv
az storage file generate-sas --path "" --share-name "fabricnlp" 

# source storage account
$srcResourceGroup = "fabrickubernetes"
$sourceAccountName = "fabrickubernetesstorage"
$sourceAccountKey = az storage account keys list -g $srcResourceGroup -n $sourceAccountName --query "[0].value" -o tsv
$sourceSASToken = az storage file generate-sas
$sourceConnectionString = az storage account show-connection-string -n $sourceAccountName -g $srcResourceGroup -o tsv

$sourceShare = "fabricnlp"

# fabric nlp
az storage share snapshot `
    --name $sourceShare `
    --account-key $sourceAccountKey `
    --account-name $sourceAccountName `
    --connection-string $sourceConnectionString


az storage blob copy start-batch `
--account-key $destAccountKey `
--account-name $destAccountName `
--connection-string $destConnectionString `
--dryrun `
--pattern "*" `
--source-account-key $sourceAccountKey `
--source-account-name $sourceAccountName `
--source-share $sourceShare


# [--destination-container]
# [--source-container]
# [--sas-token]
# [--source-sas]
# [--source-uri]
