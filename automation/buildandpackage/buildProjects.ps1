# Entry Point for Build Process

function exitWithCode ($taskName) {
    write-host
    write-host "[$scriptName] $taskName failed!" -ForegroundColor Red
    write-host
    write-host "     Returning errorlevel (-1) to DOS" -ForegroundColor Magenta
    write-host
    $host.SetShouldExit(-1)
    exit
}

function taskWarning { 
    write-host "[$scriptName] Warning, $taskName encountered an error that was allowed to proceed." -ForegroundColor Yellow
}

function itemRemove ($itemPath) { 
	if ( Test-Path $itemPath ) {
		write-host "[$scriptName] Delete $itemPath"
		Remove-Item $itemPath -Recurse 
		if(!$?){ exitWithCode("Remove-Item $itemPath") }
	}
}

function removeTempFiles { 
    if (Test-Path projectsToBuild.txt) {
        Remove-Item projectsToBuild.txt -recurse
    }

    if (Test-Path projectDirectories.txt) {
        Remove-Item projectDirectories.txt -recurse
    }
}

function pathTest ($pathToTest) { 
	if ( Test-Path $pathToTest ) {
		Write-Host "found ($pathToTest)"
	} else {
		Write-Host "none ($pathToTest)"
	}
}

$SOLUTION = $args[0]
$BUILDNUMBER = $args[1]
$REVISION = $args[2]
$ENVIRONMENT = $args[3]
$AUTOMATIONROOT=$args[4]
$ACTION = $args[5]

if (-not($SOLUTION)) {exitWithCode SOLUTION_NOT_PASSED }
if (-not($BUILDNUMBER)) {exitWithCode BUILDNUMBER_NOT_PASSED }
if (-not($REVISION)) {exitWithCode REVISION_NOT_PASSED }
if (-not($ENVIRONMENT)) {
	$ENVIRONMENT = "DEV"
	Write-Host "[$scriptName]   Environment not passed, defaulted to $ENVIRONMENT" 
}

$automationHelper="$AUTOMATIONROOT\remote"

$exitStatus = 0

$scriptName = $MyInvocation.MyCommand.Name

Write-Host "[$scriptName]   AUTOMATIONROOT : $AUTOMATIONROOT" 

$propertiesFile = "$AUTOMATIONROOT\CDAF.windows"
$propName = "productVersion"
try {
	$cdafVersion=$(& .\$AUTOMATIONROOT\remote\getProperty.ps1 $propertiesFile $propName)
	if(!$?){ taskWarning }
} catch { exitWithCode "PACK_GET_CDAF_VERSION" }
Write-Host "[$scriptName]   CDAF Version   : $cdafVersion"

# Runtime information
Write-Host "[$scriptName]   pwd            : $(pwd)"
Write-Host "[$scriptName]   Hostname       : $(hostname)" 
Write-Host "[$scriptName]   user name      : $(whoami)"

# Check for user defined solution folder, i.e. outside of automation root, if found override solution root
$solutionRoot="$AUTOMATIONROOT\solution"
foreach ($item in (Get-ChildItem -Path ".")) {
	if (Test-Path $item -PathType "Container") {
		if (Test-Path "$item\CDAF.solution") {
			$solutionRoot=$item
		}
	}
}
Write-Host "[$scriptName]   solutionRoot   : $solutionRoot" 

# Build a list of projects, based on directory names, unless an override project list file exists
$projectList = ".\$solutionRoot\buildProjects"
Write-Host �NoNewLine "[$scriptName]   Project list   : " 
pathTest $projectList

write-host 
write-host "[$scriptName] Load solution properties ..."
& .\$automationHelper\Transform.ps1 "$solutionroot\CDAF.solution" | ForEach-Object { invoke-expression $_ }

Write-Host 
Write-Host "[$scriptName] Clean temp files and folders from workspace" 
removeTempFiles
itemRemove .\*.txt
itemRemove .\*.zip
itemRemove .\*.nupkg

if (Test-Path build.tsk) {
	Write-Host 
	Write-Host "[$scriptName] build.tsk found in solution root, executing in $(pwd)" 
	Write-Host 
    # Because PowerShell variables are global, set the $WORKSPACE before invoking execution
    $WORKSPACE=$(pwd)
    & .\$automationHelper\execute.ps1 $SOLUTION $BUILDNUMBER $ENVIRONMENT "build.tsk" $ACTION
    if(!$?){ exitWithCode(".\$automationHelper\execute.ps1 $SOLUTION $BUILDNUMBER $ENVIRONMENT `"build.tsk`" $ACTION") }

} 

# If there is a custom build script in the solution root, execute this.
if (Test-Path build.ps1) {
	Write-Host 
	Write-Host "[$scriptName] build.ps1 found in solution root, executing in $(pwd)" 
	Write-Host 
    # Legacy build method, note: a .BAT file may exist in the project folder for Dev testing, by is not used by the builder
    & .\build.ps1 $SOLUTION $BUILDNUMBER $REVISION $PROJECT $ENVIRONMENT $ACTION
    if(!$?){ exitWithCode("& .\build.ps1 $SOLUTION $BUILDNUMBER $REVISION $PROJECT $ENVIRONMENT $ACTION") }
}

# Set the projects to process (default is alphabetic)
if (-not(Test-Path $projectList)) {
	foreach ($item in (Get-ChildItem -Path ".")) {
		if (Test-Path $item -PathType "Container") {
			Add-Content projectDirectories.txt $item.Name
		}
	}
} else {
	Copy-Item $projectList projectDirectories.txt
	Set-ItemProperty projectDirectories.txt -name IsReadOnly -value $false
}

# List the projects to process, i.e. only those with build script entry point
Foreach ($PROJECT in get-content projectDirectories.txt) {
	if ((Test-Path .\$PROJECT\build.ps1) -or (Test-Path .\$PROJECT\build.tsk)) {
		Add-Content projectsToBuild.txt $PROJECT
	}
}

if (-not(Test-Path projectsToBuild.txt)) {

	write-host
	write-host "[$scriptName] No project directories found containing build.ps1 or build.tsk, assuming new solution, continuing ... " -ForegroundColor Yellow

} else {

	write-host
	write-host "[$scriptName] Projects to build:"
	write-host
	Get-Content projectsToBuild.txt
	write-host

	# Process all Tasks
	Foreach ($PROJECT in get-content projectsToBuild.txt) {
    
		write-host
		write-host "[$scriptName]   --- Build Project $PROJECT start ---" -ForegroundColor Green
		write-host

		cd $PROJECT

        if (Test-Path build.tsk) {
            # Task driver support added in release 0.6.1
            $WORKSPACE=$(pwd)
		    & ..\$automationHelper\execute.ps1 $SOLUTION $BUILDNUMBER $ENVIRONMENT "build.tsk" $ACTION
		    if(!$?){ exitWithCode("..\$automationHelper\execute.ps1 $SOLUTION $BUILDNUMBER $ENVIRONMENT `"build.tsk`" $ACTION") }

        } else {
            # Legacy build method, note: a .BAT file may exist in the project folder for Dev testing, by is not used by the builder
		    & .\build.ps1 $SOLUTION $BUILDNUMBER $REVISION $PROJECT $ENVIRONMENT $ACTION
		    if(!$?){ exitWithCode("& .\build.ps1 $SOLUTION $BUILDNUMBER $REVISION $PROJECT $ENVIRONMENT $ACTION") }
        }

        cd ..

		write-host
		write-host "[$scriptName]   --- BUILD project $PROJECT successfull ---" -ForegroundColor Green
	} 

}

# Only remove temp files from workspace if action is clean, otherwise leave files for debugging and adit purposes
if ($ACTION -eq "Clean") {
    removeTempFiles
}
