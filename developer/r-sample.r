# https://www.statmethods.net/management/userfunctions.html
getdata <- function(){
sourceConnection <- odbcDriverConnect("Driver={SQL Server};Server=localhost;Database=SAM;trusted_connection=yes;")
# select here
odbcClose(sourceConnection)
return(object)
}

savedata <- function(data){
destinationConnection <- odbcDriverConnect("Driver={SQL Server};Server=localhost;Database=SAM;trusted_connection=yes;")
sqlSave(destinationConnection, data, "test.demoEntityBASE_load", rownames=FALSE, append=TRUE)
odbcClose(destinationConnection)

}

# user code here

