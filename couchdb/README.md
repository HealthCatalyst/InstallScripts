# CouchDB Backup and Restore

Provided here are several PowerShell scripts to make it easier to backup and restore your CouchDB databases. The scripts wrap the [@cloudant/couchbackup](https://www.npmjs.com/package/@cloudant/couchbackup) node package.

## Prerequisites
In order to run the below scripts you need:

1. PowerShell v5 or later.
2. Node.js 4.8.2 or later.
3. CouchDB 2.0.0 or later.
4. Network Connectivity to your CouchDB server.
5. The admin credentials for your CouchDB server.

## Backing up your database

1. Download all files from this directory: backup.ps1, restore.ps1, set-credentials.ps1, utilities.psm1.
2. Run the `set-credentials.ps1` script to save the admin password of the database in an encrypted file. Note that only the user who ran the `set-credentials.ps1` script will be able to access the encrypted password in the file.
3. Run the `backup.ps1` script following the example below. An optionally encrypted database backup file will be created in the same directory where the script is run. Note that only the user who ran the script will be able to decrypt the backup file.

## Restoring your database
1. Ensure the target database exists on the CouchDB where you want to restore the database.
2. Run the `restore.ps1` script following the example below, remembering that only the user who ran the script will be able to decrypt the backup file.

## Detailed Script Usage
### backup.ps1

Creates a backup one or more CouchDB databases. Uses DPAPI encryption to encrypt the contents of the backup to a file. The encryption is based on the user who runs the script. A single file is created per database that is backed up and named according to the following convention: [dbname]_encrypted_yyyyMMddHHmmss.db. Each backup is a full backup, the script does not support incremental backups.

#### Usage
>couchDbHost - the server hosting CouchDB  
couchDbPort - the port that CouchDb is listening on  
couchDbAdminUsername - the administrator username for CouchDB  
databaseNames - a comma delimited list of database names to backup
skipEncryption - a switch indicating if the backup file should be stored in clear text.

#### Example
```
.\backup.ps1 -couchDbHost localhost -couchDbPort 5984 -couchDbAdminUsername admin -databaseName identity,authorization
```

### restore.ps1
Restores a CouchDB database backup to a target database. This script will restore an encrypted backup file to the specified target database. Note that the target database must already exist, so if you want to restore to a new database, create that database first. Also, in order to successfully decrypt the database, the same user that performed the backup of the database must also restore the database.

#### Usage
>couchDbHost - the server hosting CouchDB  
couchDbPort - the port that CouchDb is listening on  
couchDbAdminUsername - the administrator username for CouchDB  
databaseToRestore - the name of the target database where the data will be restored  
backupFile - the path to the backup file that needs to be restored
skipDecryption - a switch indicating that the backup file is not encrypted

#### Example
```
.\couchrestore.ps1 -couchDbHost localhost -couchDbPort 5984 -couchDbAdminUsername admin -databaseToRestore identity2 -backupFile .\identity_encrypted_20171023152950.db
```

### set-credentials.ps1
Encrypts the credentials of the CouchDB admin user so the backup.ps1 and restore.ps1 scripts can authenticate to CouchDB. This is useful when scheduling the backup script to run as a job on a repeating schedule.

#### Usage
The `set-credentials.ps1` takes no parameters.

#### Example
```
.\set-credentials.ps1
```

## Limitations

Below are some noted limitations of the scripts:

1. The script uses the Windows Data Protection API (DPAPI) to encrypt both the database password as well as the backup file. This means that these can only be decrypted by the same user on the same machine. You can skip encryption in the backup script by passing the -skipEncryption switch. Similarly, you can skip decryption in the restore script by passing the -skipDecryption switch. We would recommend that you subsequently encrypt the backup files with another utility such as 7zip after they are created.
2. These scripts will only handle backing up small databases, i.e. less than 1 GB.

Since these scripts wrap the [@cloudant/couchbackup](https://www.npmjs.com/package/@cloudant/couchbackup) node package, you are free to use them as a guide to creating your own scripts for backing up an restoring your CouchDB databases.

