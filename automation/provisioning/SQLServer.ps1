Param (
  [string]$serviceAccount,
  [string]$password,
  [string]$adminAccount,
  [string]$instance,
  [string]$media
)
$scriptName = 'SQLServer.ps1'

# Common expression logging and error handling function, copied, not referenced to ensure atomic process
function executeExpression ($expression) {
	$error.clear()
	Write-Host "[$scriptName] $expression"
	try {
		$output = Invoke-Expression $expression
	    if(!$?) { Write-Host "[$scriptName] `$? = $?"; exit 1 }
	} catch { echo $_.Exception|format-list -force; exit 2 }
    if ( $error[0] ) { Write-Host "[$scriptName] `$error[0] = $error"; exit 3 }
    return $output
}

Write-Host "`nIf provisioing to server core, the management console is not installed, for GUI server,"
Write-Host "Management console will be installed."
Write-Host "`n[$scriptName] ---------- start ----------"
if ($serviceAccount) {
    Write-Host "[$scriptName] serviceAccount : $serviceAccount"
} else {
	$serviceAccount = 'sqlServiceAccount'
    Write-Host "[$scriptName] serviceAccount : $serviceAccount (default)"
}

if ($password) {
    Write-Host "[$scriptName] password       : **********"
} else {
	$password = 'password'
    Write-Host "[$scriptName] password       : ********** (default)"
}

if ($adminAccount) {
    Write-Host "[$scriptName] adminAccount   : $adminAccount"
} else {
	$adminAccount = 'BUILTIN\Administrators'
    Write-Host "[$scriptName] adminAccount   : $adminAccount (default)"
}

if ($instance) {
    Write-Host "[$scriptName] instance       : $instance"
} else {
	$instance = 'MSSQLSERVER'
    Write-Host "[$scriptName] instance       : $instance (default)"
}

if ($media) {
	if ($media -like '*$*') {
		if ($media -like '$env:*') {
			$varName = $media.Split(":")
			$loadedValue = Invoke-Expression "[Environment]::GetEnvironmentVariable(`"$($varName[1])`", `'User`')"
			if ($loadedValue) {
			    Write-Host "[$scriptName] loadedValue    : $loadedValue (from $media as user variable)"
				$media = $loadedValue
		    } else {
				$loadedValue = Invoke-Expression "[Environment]::GetEnvironmentVariable(`"$($varName[1])`", `'Machine`')"
				if ($loadedValue) {
				    Write-Host "[$scriptName] loadedValue    : $loadedValue (from $media as machine variable)"
					$media = $loadedValue
				} else {
				    Write-Host "`n[$scriptName] Unable to resolve $media, exit with LASTEXITCODE=10"; exit 10
				}
			}
		} else {
		    $media = Invoke-Expression "Write-Output $media" # Evaluate in case a session variable has been passed, i.e. $loadedVarable:\
		    Write-Host "[$scriptName] media          : $media (evaluated)"
	    }
    }
    Write-Host "[$scriptName] media          : $media"
} else {
	$media = 'D:\'
    Write-Host "[$scriptName] media          : $media (default)"
}

# Provisioning Script builder
if ( $env:PROV_SCRIPT_PATH ) {
	Add-Content "$env:PROV_SCRIPT_PATH" "executeExpression `"./automation/provisioning/$scriptName $serviceAccount `'**********`' $adminAccount $instance $media`""
}

$EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID').EditionId
write-host "[$scriptName] EditionId      : $EditionId"

if ($env:interactive) {
	Write-Host
    Write-Host "[$scriptName]   env:interactive is set ($env:interactive), run in current window"
    $sessionControl = '-PassThru -Wait -NoNewWindow'
	$logToConsole = 'true'
} else {
    $sessionControl = '-PassThru -Wait'
	$logToConsole = 'false'
}

$executable = Get-ChildItem $media -Filter *.exe

# Reference: https://msdn.microsoft.com/en-us/library/ms144259.aspx
$argList = @(
	'/Q',
	'/ACTION="Install"',
	"/INDICATEPROGRESS=$logToConsole",
	'/IACCEPTSQLSERVERLICENSETERMS',
	'/ENU=true',
	'/UPDATEENABLED=false',
	"/FEATURES=SQL",
	'/INSTALLSHAREDDIR="C:\Program Files\Microsoft SQL Server"',
	"/INSTANCENAME=`"$instance`"",
	'/INSTANCEDIR="C:\Program Files\Microsoft SQL Server"',
	'/SQLSVCSTARTUPTYPE="Automatic"',
	'/SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"',
	"/SQLSVCACCOUNT=`"$serviceAccount`"",
	"/SQLSVCPASSWORD=`"$password`"",
	"/SQLSYSADMINACCOUNTS=`"$adminAccount`"",
	'/TCPENABLED=1',
	'/NPENABLED=1'
)
Write-Host
executeExpression "`$proc = Start-Process -FilePath `"$media$executable`" -ArgumentList `'$argList`' $sessionControl"

foreach ( $sqlVersions in Get-ChildItem "C:\Program Files\Microsoft SQL Server\" ) {
	$logPath = $sqlVersions.FullName + '\Setup Bootstrap\Log\Summary.txt'
	if ( Test-Path $logPath ) {
		$result = cat $logPath | findstr "Failed:"
		if ($result) {
			Write-Host
		    Write-Host "[$scriptName] `'Failed:`' found in $logPath, first 40 lines follow ..."
			Get-Content $logPath | select -First 40
		    Write-Host "[$scriptName] Exit with LASTEXITCODE = 20"; exit 20
		}
	} 
}

Write-Host
Write-Host "[$scriptName] ---------- stop ----------"
exit 0