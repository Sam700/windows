# Manual process for VirtualBox Image Construction

Working on building using Packer. Will create 3 stage scripting as preparation in next (1.5.3) CDAF release.

## Image Preparation

* Disable EIP in Server Management then disable Server Management automatically opening

Enable Remote Desktop and Open firewall

    $obj = Get-WmiObject -Class "Win32_TerminalServiceSetting" -Namespace root\cimv2\terminalservices
    $obj.SetAllowTsConnections(1,1)
    Set-NetFirewallRule -Name RemoteDesktop-UserMode-In-TCP -Enabled True

Disable User Account Controls (UAC)

    reg add HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA /d 0 /t REG_DWORD /f /reg:64

Ensure all adapters set to private

    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private  

configure the computer to receive [remote commands](http://technet.microsoft.com/en-us/library/hh849694.aspx)

    Enable-PSRemoting -Force

Disable password policy

    secedit /export /cfg c:\secpol.cfg
    (gc C:\secpol.cfg).replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Out-File C:\secpol.cfg
    secedit /configure /db c:\windows\security\local.sdb /cfg c:\secpol.cfg /areas SECURITYPOLICY
    rm -force c:\secpol.cfg -confirm:$false

Set default Administrator password to "vagrant"

    $admin=[adsi]"WinNT://./Administrator,user"
    $admin.SetPassword("vagrant")
    $admin.UserFlags.value = $admin.UserFlags.value -bor 0x10000 # Password never expires
    $admin.CommitChanges() 

Create the Vagrant user (with password vagrant) in the local administrators group

    $ADSIComp = [ADSI]"WinNT://$Env:COMPUTERNAME,Computer"
    $LocalUser = $ADSIComp.Create("User", "vagrant")
    $LocalUser.SetPassword("vagrant")
    $LocalUser.SetInfo()
    $LocalUser.FullName = "Vagrant Administrator"
    $LocalUser.SetInfo()
    $LocalUser.UserFlags.value = $LocalUser.UserFlags.value -bor 0x10000 # Password never expires
    $LocalUser.CommitChanges()
    $de = [ADSI]"WinNT://$env:computername/Administrators,group"
    $de.psbase.Invoke("Add",([ADSI]"WinNT://$env:computername/vagrant").path)

Open Firewall for WinRM

    Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any

Allow arbitrary script execution

    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force

Allow "hop"

    Enable-WSManCredSSP -Role Server -Force

### Insert Guest Additions CD image and reboot from prompt

    D:\VBoxWindowsAdditions-amd64.exe

### On host (in VirtualBox) remove media

After reboot, logon as vagrant via remote PowerShell to verify access

    $securePassword = ConvertTo-SecureString 'vagrant' -asplaintext -force
    $cred = New-Object System.Management.Automation.PSCredential ('vagrant', $securePassword)
    enter-pssession 127.0.0.1 -port 15985 -Auth CredSSP -credential $cred 

exit and return to remote desktop, settings to support Vagrant integration, Unencypted Remote PowerShell

    winrm set winrm/config '@{MaxTimeoutms="1800000"}'
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    winrm set winrm/config/client/auth '@{Basic="true"}'

### Apply windows updates

Server 2016 or above (likely to reboot automatically)...

    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PSWindowsUpdate -Confirm:$False
    Import-Module PSWindowsUpdate
    Get-WUInstall -Verbose -AcceptAll -AutoReboot:$True -Confirm:$False

## Recover Disk space

Remove the features that are not required, then remove media for available features that are not installed

    @('Server-Media-Foundation', 'Powershell-ISE') | Remove-WindowsFeature
    Get-WindowsFeature | ? { $_.InstallState -eq 'Available' } | Uninstall-WindowsFeature -Remove

Clean up Windows Updates and WinSXS, then optimise disk

    Stop-Service wuauserv
    Remove-Item  $env:systemroot\SoftwareDistribution -Recurse -Force
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
    Optimize-Volume -DriveLetter C

Cleanup Trim pagefile (windows rebuilds that on start-up)

    $System = GWMI Win32_ComputerSystem -EnableAllPrivileges
    $System.AutomaticManagedPagefile = $False
    $System.Put()
    $CurrentPageFile = gwmi -query "select * from Win32_PageFileSetting where name='c:\\pagefile.sys'"
    $CurrentPageFile.InitialSize = 512
    $CurrentPageFile.MaximumSize = 512
    $CurrentPageFile.Put()

Use [sysinternals guidance](http://huestones.co.uk/node/305), important especially for VirtualBox

    cd ~
    $zipFile = "SDelete.zip"
    $url = "https://download.sysinternals.com/files/$zipFile"
    (New-Object System.Net.WebClient).DownloadFile($url, "$PWD\$zipFile") 
    Add-Type -AssemblyName System.IO.Compression.FileSystem 
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD\$zipfile", "$PWD") 
    ./sdelete.exe -z c:

### Sysprep (Results in host shutdown)

Perform from console or RDP as this will close the WinRM (Remote Powershell) connections [in the link, name="WinRM-HTTP"](https://github.com/mitchellh/vagrant/issues/7680), see also [Microsoft guide](https://technet.microsoft.com/en-us/library/cc766314(v=ws.10).aspx)

    mkdir -Path $env:windir/setup/scripts/
    Add-Content $env:windir/setup/scripts/SetupComplete.cmd 'netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-in)" new action=allow'
    cat $env:windir/setup/scripts/SetupComplete.cmd
    netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-in)" new action=block

As per this [URL](https://technet.microsoft.com/en-us/library/cc749415(v=ws.10).aspx) there are implicit places windows looks for unattended files, I'm using C:\Windows\Panther\Unattend

    cd ~
    (New-Object System.Net.WebClient).DownloadFile('http://cdaf.io/static/app/downloads/unattend.xml', "$PWD\unattend.xml")
    mkdir C:\Windows\Panther\Unattend
    Copy-Item $PWD\unattend.xml C:\Windows\Panther\Unattend\
    cat C:\Windows\Panther\Unattend\unattend.xml
    C:\windows\system32\sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\Panther\Unattend\unattend.xml

# On the host

Compress the HDD and pack the image

    $boxName = 'WindowsServer'
    mkdir build;cd build
    $packageFile = $boxname + '.box'
    & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyhd "$env:userprofile\VirtualBox VMs\${boxName}\${boxName}.vdi" --compact
    (New-Object System.Net.WebClient).DownloadFile('http://cdaf.io/static/app/downloads/Vagrantfile', "$PWD\Vagrantfile") 
    vagrant package --base $boxName --output $packageFile --vagrantfile Vagrantfile
    vagrant box add $boxName $packageFile --force

Test time

    mkdir temp
    cd temp
    vagrant init $boxName
    vagrant up
    vagrant powershell default

Now clean-up

    vagrant destroy -f
    cd ..; Remove-Item temp -Force -Recurse
    vagrant box remove $boxName