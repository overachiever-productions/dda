Set-StrictMode -Version 3.0;

# NOTE: 
# 		REQUIRES PSI 0.3.6+ 
# 			https://github.com/overachiever-productions/psi
Import-Module -Name psi -Version 0.3.7 -Force;

[string]$ScriptRoot = $PSScriptRoot;
[string]$ProjectRoot = (Get-Item -Path $ScriptRoot).Parent;

function Build-DdaTestEnvironment {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$TargetSqlServer,
		[Parameter(Mandatory)]
		[string]$TargetDatabase,
		[PSCredential]$SqlCredential,
		[Switch]$Force = $false  		# When true, will DROP/OVERWRITE $TargetDatabase if it already exists. 
	);
	
	begin {
		[bool]$succeded = $false;
	}
	
	process {
		
		# ====================================================================================================
		# Test Connectivity + Handle "If-Exists" vs $TargetDatabase:
		# ====================================================================================================	
		$results = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database "master" -SqlCredential $SqlCredential `
									 -Query "SELECT [database_id] FROM sys.databases WHERE [name] = @target" -ParameterString "@target sysname = $TargetDatabase";
		
		if ($results) {
			if ($false -eq $Force) {
				throw "Specified -TargetDatabase )[$TargetDatabase]) already exists. Use -Force DROP/overwrite - or specify a different -TargetDatabase.";
			}
			
			$ddl = "USE [master];`r`nALTER DATABASE [$TargetDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;`r`nDROP DATABASE [$TargetDatabase];";
			
			$ddlResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database "master" -SqlCredential $SqlCredential -Query $ddl -AsObject;
			
			# TODO: put this in a FUNC... 
			if ($ddlResults.HasErrors) {
				foreach ($ddlError in $ddlResults.Errors) {
					Write-Error $ddlError.Summarize();
				}
				return;
			}
		}
		
		# ====================================================================================================
		# Create and (Minimally) Configure $TargetDatabase:
		# ====================================================================================================	
		$ddl = "SET NOCOUNT ON;`r`nUSE [master];`r`nCREATE DATABASE [$TargetDatabase];`r`n";
		$ddlResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database "master" -SqlCredential $SqlCredential -Query $ddl -AsObject;
		
		# TODO: put this in a FUNC... 
		if ($ddlResults.HasErrors) {
			foreach ($ddlError in $ddlResults) {
				Write-Error $ddlError.Summarize();
			}
			return;
		}
		
		$ddl = "ALTER AUTHORIZATION ON DATABASE::[$TargetDatabase] TO [sa];`r`nALTER DATABASE [$TargetDatabase] SET RECOVERY SIMPLE;`r`nALTER DATABASE [$TargetDatabase] SET DISABLE_BROKER;";
		$ddlResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database "master" -SqlCredential $SqlCredential -Query $ddl -AsObject;
		
		# TODO: put this in a FUNC... 
		if ($ddlResults.HasErrors) {
			foreach ($ddlError in $ddlResults) {
				Write-Error $ddlError.Summarize();
			}
			return;
		}
		
		# ====================================================================================================
		# Deploy tSQLt:
		# ====================================================================================================		
		
		# tSQLt is a fuggin' mess Doesn't work via Invoke-PsiCommand, doesn't work via Invoke-SqlCmd. 
		# 		cuz... it's using #tempSprocs up the wazoo. 
		
		$tSQLtPath = Join-Path -Path $ScriptRoot -ChildPath "tSQLt.server.sql";
		
		$arguments = @();
		$arguments += "-S '$TargetSqlServer' ";
		$arguments += "-d '$TargetDatabase' ";
		#$arguments += "-Q 'SELECT DB_NAME();' ";
		$arguments += "-i '$tSQLtPath' ";
		
		if ($SqlCredential) {
			$arguments += "-U '$($SqlCredential.UserName)' ";
			$arguments += "-P '$($SqlCredential.GetNetworkCredential().Password)' ";
		}
		
		$sqlCmdCmd = "& sqlcmd ";
		foreach ($arg in $arguments) {
			$sqlCmdCmd += $arg;
		}
		
		$outcome = Invoke-Expression $sqlCmdCmd;
		
		Write-Host "-------------------------------------------------";
		Write-Host "tSQLt - Server: ";
		Write-Host $outcome;
		
		# -------------------------------------------------------------------------------------
		$tSQLtPath = Join-Path -Path $ScriptRoot -ChildPath "tSQLt.database.sql";
		$arguments = @();
		$arguments += "-S '$TargetSqlServer' ";
		$arguments += "-d '$TargetDatabase' ";
		$arguments += "-i '$tSQLtPath' ";
		
		if ($SqlCredential) {
			$arguments += "-U '$($SqlCredential.UserName)' ";
			$arguments += "-P '$($SqlCredential.GetNetworkCredential().Password)' ";
		}
		
		$sqlCmdCmd = "& sqlcmd ";
		foreach ($arg in $arguments) {
			$sqlCmdCmd += $arg;
		}
		
		#Write-Host $sqlCmdCmd;
		$outcome = Invoke-Expression $sqlCmdCmd;
		
		Write-Host "-------------------------------------------------";
		Write-Host "tSQLt - Database: ";
		Write-Host $outcome;
		
		
#		$tSQLtPath = Join-Path -Path $ScriptRoot -ChildPath "tSQLt.server.sql";
#		$tSQLtResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database "master" -SqlCredential $SqlCredential -File $tSQLtPath -AsObject;
#		
#		if ($tSQLtResults.HasErrors) {
#			foreach ($tSQLtError in $tSQLtResults) {
#				Write-Error $tSQLtError.Message;
#			}
#			return;
#		}
		
#		$tSQLtPath = Join-Path -Path $ScriptRoot -ChildPath "tSQLt.database.sql";
#		
#		$tSQLtResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $tSQLtPath -AsObject;
#		
#		if ($tSQLtResults.HasErrors) {
#			foreach ($tSQLtError in $tSQLtResults) {
#				Write-Error $tSQLtError.Summarize;
#			}
#			return;
#		}
#		
#		foreach ($message in $tSQLtResults.Messages) {
#			Write-Host "-----------------------------------------------------------";
#			Write-Host $message;
#		}
		
		# ====================================================================================================
		# Deploy dda:
		# ====================================================================================================			
		$ddaPath = Join-Path -Path $ProjectRoot -ChildPath "\deployment\dda_latest.sql";
		
		# hmmmm: 
		#$ddaResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $ddaPath -AsObject;
		
		$arguments = @();
		$arguments += "-S '$TargetSqlServer' ";
		$arguments += "-d '$TargetDatabase' ";
		$arguments += "-i '$ddaPath' ";
		
		if ($SqlCredential) {
			$arguments += "-U '$($SqlCredential.UserName)' ";
			$arguments += "-P '$($SqlCredential.GetNetworkCredential().Password)' ";
		}
		
		$sqlCmdCmd = "& sqlcmd ";
		foreach ($arg in $arguments) {
			$sqlCmdCmd += $arg;
		}
		
		$outcome = Invoke-Expression $sqlCmdCmd;
		
		Write-Host "-------------------------------------------------";
		Write-Host "dda - deployment: ";
		Write-Host $outcome;
		
		# ====================================================================================================
		# Create test tables and other testing objects in $TestDatabase:
		# ====================================================================================================	
		$ddaTestPath = Join-Path -Path $ScriptRoot -ChildPath "create_test_environment.sql";
		
		$ddaTestResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $ddaTestPath -AsObject;
		Write-Host "-------------------------------------------------";
		Write-Host "DDA - Test Objects: ";
		if ($ddaTestResults.HasErrors) {
			foreach ($tSQLtError in $ddaTestResults) {
				Write-Error $tSQLtError.Summarize;
			}
			return;
		}
		
		# ====================================================================================================
		# Deploy All Tests:
		# ====================================================================================================	
		$files = Get-ChildItem -Path (Join-Path -Path $ProjectRoot -ChildPath "\tests\capture\") -Filter "*.sql";
		$testsResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $files -AsObject;
		
		$files = Get-ChildItem -Path (Join-Path -Path $ProjectRoot -ChildPath "\tests\json\") -Filter "*.sql";
		$testsResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $files -AsObject;
		
		$files = Get-ChildItem -Path (Join-Path -Path $ProjectRoot -ChildPath "\tests\projection\") -Filter "*.sql";
		$testsResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $files -AsObject;
		
		$files = Get-ChildItem -Path (Join-Path -Path $ProjectRoot -ChildPath "\tests\translation\") -Filter "*.sql";
		$testsResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $files -AsObject;
		
		$files = Get-ChildItem -Path (Join-Path -Path $ProjectRoot -ChildPath "\tests\utilities\") -Filter "*.sql";
		$testsResults = Invoke-PsiCommand -SqlInstance $TargetSqlServer -Database $TargetDatabase -SqlCredential $SqlCredential -File $files -AsObject;
	};
	
	end {
		
	};
}


$creds = Get-Credential -UserName sa;

Build-DdaTestEnvironment -TargetSqlServer "dev.sqlserver.id" -TargetDatabase "dda_test" -SqlCredential $creds -Force;



