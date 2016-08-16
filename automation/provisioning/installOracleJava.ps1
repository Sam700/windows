# Common expression logging and error handling function, copied, not referenced to ensure atomic process
function executeExpression ($expression) {
	$error.clear()
	Write-Host "[$scriptName] $expression"
	try {
		Invoke-Expression $expression
	    if(!$?) { Write-Host "[$scriptName] `$? = $?"; exit 1 }
	} catch { echo $_.Exception|format-list -force; exit 2 }
    if ( $error[0] ) { Write-Host "[$scriptName] `$error[0] = $error"; exit 3 }
}

$scriptName = 'installOracleJava.ps1'

Write-Host
Write-Host "[$scriptName] ---------- start ----------"

$java_version = $args[0]
if ( $java_version ) {
	Write-Host "[$scriptName] java_version          : $java_version"
} else {
	$java_version = '8u101'
	Write-Host "[$scriptName] java_version          : $java_version (default)"
}

$sourceInstallDir = $args[1]
if ( $sourceInstallDir ) {
	Write-Host "[$scriptName] sourceInstallDir      : $sourceInstallDir"
} else {
	$sourceInstallDir = 'c:\vagrant\.provision'
	Write-Host "[$scriptName] sourceInstallDir      : $sourceInstallDir (default)"
}

$destinationInstallDir = $args[2]
if ( $destinationInstallDir ) {
	Write-Host "[$scriptName] destinationInstallDir : $destinationInstallDir"
} else {
	$destinationInstallDir = 'c:\Java'
	Write-Host "[$scriptName] destinationInstallDir : $destinationInstallDir (default)"
}

Write-Host

# The installation directory for JDK, the script will create this
$javaInstallDir = "$destinationInstallDir\Java"
$jdkInstallDir = "$javaInstallDir\jdk$java_version"
$jreInstallDir = "$javaInstallDir\jre$java_version"
$jdkInstallFileName = "jdk-" + $java_version + "-windows-x64.exe"
try {
	New-Item -path $javaInstallDir -type directory -force | Out-Null
} catch {
	Write-Host "Java Install Exception: $_.Exception.Message" -ForegroundColor Red
	throw $_
}

Write-Host "  Installing the JDK ..."
Write-Host "    Installer : $sourceInstallDir\$jdkInstallFileName"

# Arguments which switch the JDK install to a silent process with no reboots, and sets up the log directory
$arguments =@("/s /INSTALLDIRPUBJRE=`"$jreInstallDir`" INSTALL_SILENT=Enable REBOOT=Disable INSTALLDIR=`"$jdkInstallDir`"")
Write-Host "    Arguments : $arguments"
Write-Host
Write-Host "    Installing the JDK ..."

try {
	$proc = Start-Process -FilePath "$sourceInstallDir\$jdkInstallFileName" -ArgumentList $arguments  -Wait -PassThru

	if($proc.ExitCode -ne 0) {
		Write-Host "Failure : Start-Process -FilePath `"$sourceInstallDir\$jdkInstallFileName`" -ArgumentList $arguments  -Wait -PassThru" -ForegroundColor Red
		throw JDK_INSTALL_ERROR 
	}
} catch {
	Write-Host "Exception : Start-Process -FilePath `"$sourceInstallDir\$jdkInstallFileName`" -ArgumentList $arguments  -Wait -PassThru" -ForegroundColor Red
	throw $_
}
Write-Host "  Installing the JDK complete."
Write-Host

# Configure environment variables
Write-Host "  Configuring environment variables ..."
Write-Host
[System.Environment]::SetEnvironmentVariable("JAVA_HOME", "$jdkInstallDir", "Machine")
$pathEnvVar=[System.Environment]::GetEnvironmentVariable("PATH","Machine")
[System.Environment]::SetEnvironmentVariable("PATH", $pathEnvVar + ";$jdkInstallDir\bin", "Machine")
Write-Host
Write-Host "  Configuring environment complete."
Write-Host

Write-Host
Write-Host "[$scriptName] ---------- stop -----------"
Write-Host
