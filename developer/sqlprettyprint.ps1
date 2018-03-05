<#  
.SYNOPSIS  
    'Pretty print' a given T-SQL script

.DESCRIPTION  
    This script will format T-SQL scripts

.NOTES  
    Author     : Arvind Shyamsundar (arvindsh@microsoft.com)
  
.PARAMETERS
	-SourceFile:   full file path to the file containing the input T-SQL
	-SourceScript: string containing T-SQL
  -ReturnParsedFragment: a switch that returns the parsed tokens

.LIMITATIONS
	T-SQL comments are not preserved

.LINK  
    http://blogs.msdn.com/b/arvindsh
	
.HISTORY
	2013.02.28	First version for blog
    2013.04.05  updated by jake heidt (admin@jheidt.com) to accept strings or files, and to use the pipeline
#>
function Format-Sql
{    
    [CmdletBinding()]
    param
    (
        [parameter(Position=0,Mandatory=$true,ParameterSetName='SourceFromFile',ValueFromPipeline=$true)]
        [ValidateNotNull()]
	    [System.IO.FileInfo[]]$SourceFile=($null),

        [parameter(Position=0,Mandatory=$true,ParameterSetName='SourceFromString',ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [string[]]$SourceScript=($null),

        [parameter(Position=1)]
        [switch]$ReturnParsedFragment=$false
    )

begin 
{
    Write-Debug "Parameter set: $($PSCmdlet.ParameterSetName)"
    switch($PSCmdlet.ParameterSetName)
    {
        SourceFromFile   { if($SourceFile.Length   -eq 0) { throw "Please specify at least one source file" } }
        SourceFromString { if($SourceScript.Length -eq 0) { throw "Please specify at least one sql script"  } }
    }
    $sqldom = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.TransactSql.ScriptDom")
    if($sqldom -eq $null) { throw "Could not load Microsoft.SqlServer.TransactSql.ScriptDom - install SQLDOM.MSI from the latest SQL Server Feature Pack" }
} <# /begin #>

process 
{
    [Microsoft.SqlServer.TransactSql.ScriptDom.TSql110Parser]$parser = New-Object -TypeName Microsoft.SqlServer.TransactSql.ScriptDom.TSql110Parser -ArgumentList @($false)
    if($parser -eq $null) { throw "Could not create parser 'TSql110Parser' - install SQLDOM.MSI from the SQL 2012 Feature Pack" }

    [Microsoft.SqlServer.TransactSql.ScriptDom.Sql110ScriptGenerator]$scriptgen = New-Object -TypeName Microsoft.SqlServer.TransactSql.ScriptDom.Sql110ScriptGenerator

    # determine what we are going to loop over - strings or files
    switch($PSCmdlet.ParameterSetName) 
    { 
        'SourceFromFile'   { $to_enumerate = $SourceFile   }
        'SourceFromString' { $to_enumerate = $SourceScript }
    }

    [System.IO.TextReader]$reader = $null

    $to_enumerate | %{    
    
        $iter = $_ # need to store pipeline value to a local, since $_ seems to rebind if the following switch {} 
        
        switch( $PSCmdlet.ParameterSetName ) 
        {
            'SourceFromFile'
            { 
                if(!(Test-Path -Path "$($iter.FullName)"))
                { 
                    Write-Error "File '$($iter.FullName)' does not exist"
                    continue
                }
                $reader = [System.IO.StreamReader](New-Object -TypeName 'System.IO.StreamReader' -ArgumentList @($iter))
            }
            'SourceFromString'  
            { 
                if([string]::IsNullOrWhiteSpace($iter)) 
                { 
                    Write-Error "SQL script string is null or blank"
                    continue
                }
                $reader = [System.IO.StringReader](New-Object -TypeName 'System.IO.StringReader' -ArgumentList @($iter))
            }
        }
        
        [System.Collections.Generic.IList[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]]$parser_errors = New-Object -TypeName 'System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]'
        
        $tsqlfrag = $parser.Parse( $reader, [ref]$parser_errors )

        $reader.Dispose()
        $reader = $null
                
        $parser_errors | %{ 
            [Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]$pe = $_
            Write-Error "Error in parsed script: `r`n    Line   : $($pe.Line)`r`n    Column : $($pe.Column)`r`n    Message: $($pe.Message)`r`n    Number : $($pe.Number)"
        }
        
        $sql_output_writer = New-Object -TypeName 'System.IO.StringWriter' 

        $scriptgen.GenerateScript( $tsqlfrag, $sql_output_writer )

        $final_sql_script = $sql_output_writer.ToString()

        $sql_output_writer.Dispose()
        $sql_output_writer = $null

        if($ReturnParsedFragment) {
            Write-Output @($final_sql_script, $tsqlfrag)
        } else {
            Write-Output $final_sql_script
        }        
    }
} <# /process #>

end 
{
    $scriptgen = $null
    $parser    = $null
} <# /end #>

} 


#
# example usage
#

$sql_statements = @(
    'SELECT 1 FROM [TABLE]'
    'SELECT [email] FROM [users] WHERE [username] = @username AND [passwordhash] = @pwdhash'
    'UPDATE [users] SET [passwordhash] = @pwdhash WHERE [username] = @username'
)
# Format-Sql -SourceScript $sql_statements

Format-Sql -SourceFile "C:\Temp\test.sql"
#
# $sql, $frag = Format-Sql -SourceScript $example_sql_statement -ReturnParsedFragment
#
# $frag.ScriptTokenStream | ?{ $_.TokenType -ne 'WhiteSpace' } | Select-Object TokenType, Text  | ft -AutoSize -Wrap
#