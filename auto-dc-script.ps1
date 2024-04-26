# Static IP, default Gateway and DNS variables

$IP = "192.168.1.100"
$MaskBits = 24 # This means /24 CIDR block, or subnet mask 255.255.255.0
$Gateway = "192.168.1.1"
$DNS = "1.1.1.1"
$IPType = "IPv4"

# Retrieve the network adapter that you want to configure

$adapter = Get-NetAdapter | ? {$_.Status -eq "up"}

# Remove any existing IP, gateway from our ipv4 adapter

If (($adapter | Get-NetIPConfiguration).IPv4Address.IPAddress) {
 $adapter | Remove-NetIPAddress -AddressFamily $IPType -Confirm:$false
}
If (($adapter | Get-NetIPConfiguration).Ipv4DefaultGateway) {
 $adapter | Remove-NetRoute -AddressFamily $IPType -Confirm:$false
}

 # Configure the IP address and default gateway

$adapter | New-NetIPAddress `
 -AddressFamily $IPType `
 -IPAddress $IP `
 -PrefixLength $MaskBits `
 -DefaultGateway $Gateway

# Configure the DNS client server IP addresses

$adapter | Set-DnsClientServerAddress -ServerAddresses $DNS

# Rename the machine

Rename-Computer -NewName "STWServer"

# Install AD-Domain-Services

Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Elevate to Domain Controller and create AD Forest

$domainAdmin = "Administrator"
$domainPassword = ConvertTo-SecureString "Benfica2024!" -AsPlainText -Force
$domainAdminCredential = New-Object System.Management.Automation.PSCredential ($domainAdmin, $domainPassword)

Install-ADDSForest `
    -DomainName "suntowater.site" `
    -DomainNetbiosName "SUNTOWATER" `
    -DomainMode "WinThreshold" `
    -ForestMode "WinThreshold" `
    -InstallDNS `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "Benfica2024!" -AsPlainText -Force) `
    -Force `

# Configure DNS service (with Google DNS and Cloudflare DNS as forwarders)

Install-WindowsFeature -Name DNS -IncludeManagementTools
Add-DnsServerPrimaryZone -Name "suntowater.site" -ZoneFile "suntowater.site.dns"
Set-DnsServerForwarder -IPAddress 1.1.1.1, 8.8.8.8
Add-DnsServerResourceRecordA -Name "www" -ZoneName "suntowater.site" -IPv4Address "192.168.1.100" -CreatePtr

# Initial setup for Windows Server RADIUS (couldn't verify if it's working fully due to not having the same virtual environment as the project target)

Install-WindowsFeature -Name NPAS -IncludeManagementTools
New-NpsRadiusClient -Name "SunToWater" -Address "192.168.2.1" -SharedSecret "secretosdeporco"
Set-NpsRadiusServerSettings -AccountingOnOff $true -NpsDnsDomain "suntowater.site"
Set-NpsRadiusAuthentication -EapTls $true -EapTlsCipherSuite "TLS_RSA_WITH_AES_128_CBC_SHA256"
Start-Service "IAS"

# RADIUS check

Get-NpsRadiusClient
Get-NpsConnectionRequestPolicy
Get-NpsNetworkPolicy

# Create Organizational Units

New-ADOrganizationalUnit -Name "CEO" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "CSO" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "HR" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "IT" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "Security" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "Finances" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "Marketing" -Path "DC=suntowater,DC=site"
New-ADOrganizationalUnit -Name "Management" -Path "DC=suntowater,DC=site"

# Define the CSV file location and import the data
$Csvfile = "C:\temp\ImportADUsers.csv"
$Users = Import-Csv $Csvfile

# The password for the new user
$Password = "P@ssw0rd1234"

# Import the Active Directory module
Import-Module ActiveDirectory

# Loop through each user
foreach ($User in $Users) {
    try {
        # Retrieve the Manager distinguished name
        $managerDN = if ($User.'Manager') {
            Get-ADUser -Filter "DisplayName -eq '$($User.'Manager')'" -Properties DisplayName |
            Select-Object -ExpandProperty DistinguishedName
        }

        # Define the parameters using a hashtable
        $NewUserParams = @{
            Name                  = "$($User.'First name') $($User.'Last name')"
            GivenName             = $User.'First name'
            Surname               = $User.'Last name'
            DisplayName           = $User.'Display name'
            SamAccountName        = $User.'User logon name'
            UserPrincipalName     = $User.'User principal name'
            StreetAddress         = $User.'Street'
            City                  = $User.'City'
            State                 = $User.'State/province'
            PostalCode            = $User.'Zip/Postal Code'
            Country               = $User.'Country/region'
            Title                 = $User.'Job Title'
            Department            = $User.'Department'
            Company               = $User.'Company'
            Manager               = $managerDN
            Path                  = $User.'OU'
            Description           = $User.'Description'
            Office                = $User.'Office'
            OfficePhone           = $User.'Telephone number'
            EmailAddress          = $User.'E-mail'
            MobilePhone           = $User.'Mobile'
            AccountPassword       = (ConvertTo-SecureString "$Password" -AsPlainText -Force)
            Enabled               = if ($User.'Account status' -eq "Enabled") { $true } else { $false }
            ChangePasswordAtLogon = $true # Set the "User must change password at next logon"
        }

        # Add the info attribute to OtherAttributes only if Notes field contains a value
        if (![string]::IsNullOrEmpty($User.Notes)) {
            $NewUserParams.OtherAttributes = @{info = $User.Notes }
        }

        # Check to see if the user already exists in AD
        if (Get-ADUser -Filter "SamAccountName -eq '$($User.'User logon name')'") {

            # Give a warning if user exists
            Write-Host "A user with username $($User.'User logon name') already exists in Active Directory." -ForegroundColor Yellow
        }
        else {
            # User does not exist then proceed to create the new user account
            # Account will be created in the OU provided by the $User.OU variable read from the CSV file
            New-ADUser @NewUserParams
            Write-Host "The user $($User.'User logon name') is created successfully." -ForegroundColor Green
        }
    }
    catch {
        # Handle any errors that occur during account creation
        Write-Host "Failed to create user $($User.'User logon name') - $($_.Exception.Message)" -ForegroundColor Red
    }
}
