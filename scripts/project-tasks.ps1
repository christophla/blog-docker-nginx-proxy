<#
.SYNOPSIS
	Orchestrates docker containers.
.PARAMETER Clean
	Removes the image and kills all containers based on that image.
.PARAMETER Compose
	Builds and runs a Docker image.
.PARAMETER ComposeForDebug
	Builds and debugs a Docker image.
.PARAMETER Setup
	Setup the project (nginx proxy certs).
.PARAMETER Environment
	The environment to compose, defaults to development (docker-compose.yml)
.EXAMPLE
	C:\PS> .\project-tasks.ps1 -Compose -Environment integration 
#>

# #############################################################################
# Params
#
[CmdletBinding(PositionalBinding = $false)]
Param(
    [Switch]$Clean,
    [Switch]$Compose,
    [Switch]$ComposeForDebug,
    [Switch]$Setup,
    [ValidateNotNullOrEmpty()]
    [String]$Environment = "development"
)


# #############################################################################
# Settings
#
$CertificatePrefix = "nginx-proxy-app.com"
$Environment = $Environment.ToLowerInvariant()
$HostsDomain = "nginx-proxy-app.com"
$HostsFile = "C:\Windows\System32\drivers\etc\hosts"
$HostsIP = "127.0.0.1"


# #############################################################################
# Kills all running containers of an image
#
Function CleanAll () {

    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"
    Write-Host "+ Cleaning projects and docker images           " -ForegroundColor "Green"
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"

    dotnet clean
    
    $composeFileName = "docker-compose.yml"
    If ($Environment -ne "development") {
        $composeFileName = "docker-compose.$Environment.yml"
    }

    If (Test-Path $composeFileName) {
        docker-compose -f "$composeFileName" -p $ProjectName down --rmi all

        $danglingImages = $(docker images -q --filter 'dangling=true')
        If (-not [String]::IsNullOrWhiteSpace($danglingImages)) {
            docker rmi -f $danglingImages
        }
        Write-Host "Removed docker images" -ForegroundColor "Yellow"
    }
    else {
        Write-Error -Message "Environment '$Environment' is not a valid parameter. File '$composeFileName' does not exist." -Category InvalidArgument
    }
}


# #############################################################################
# Compose docker images
#
Function Compose () {

    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"
    Write-Host "+ Composing docker images                       " -ForegroundColor "Green"
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"

    # Fix for binding sock in docker 18.x on windows
    # https://github.com/docker/for-win/issues/1829
    $Env:COMPOSE_CONVERT_WINDOWS_PATHS=1

    $composeFileName = "docker-compose.yml"
    If ($Environment -ne "development") {
        $composeFileName = "docker-compose.$Environment.yml"
    }

    If (Test-Path $composeFileName) {

        Write-Host "Building the image..." -ForegroundColor "Yellow"
        docker-compose -f "$composeFileName" build

        Write-Host "Creating the container..." -ForegroundColor "Yellow"
        docker-compose -f $composeFileName kill
        docker-compose -f $composeFileName up -d
    }
    else {
        Write-Error -Message "Environment '$Environment' is not a valid parameter. File '$composeFileName' does not exist." -Category InvalidArgument
    }
}


# #############################################################################
# Setup the Nginx proxy.
#
Function SetupProxy () {

    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"
    Write-Host "+ Setting up nginx proxy                        " -ForegroundColor "Green"
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++" -ForegroundColor "Green"

    Write-Host "Removing existings certIficates..." -ForegroundColor "Yellow"
    Get-ChildItem -Path cert:\LocalMachine -DnsName "*$($CertificatePrefix)*" | Remove-Item

    Write-Host "Generating new certIficate" -ForegroundColor "Yellow"

    New-Item -ItemType Directory -Force -Path "certs"
    Remove-Item certs\*.*

    # generate key
    openssl `
        genrsa `
        -out "certs\$($CertificatePrefix).key" `
        4096

    # generate csr request
    openssl `
        req `
        -new `
        -sha256 `
        -out "certs\$($CertificatePrefix).csr" `
        -key "certs\$($CertificatePrefix).key" `
        -config openssl-san.conf

    #generate certIficate from csr request
    openssl `
        x509 `
        -req `
        -days 3650 `
        -in "certs\$($CertificatePrefix).csr" `
        -signkey "certs\$($CertificatePrefix).key" `
        -out "certs\$($CertificatePrefix).crt" `
        -extensions req_ext `
        -extfile openssl-san.conf

    # generate pem
    cat "certs\$($CertificatePrefix).crt", "certs\$($CertificatePrefix).key" | sc "certs\$($CertificatePrefix).pem"

    # install certIficate
    $certIficate = ( Get-ChildItem -Path "certs\$($CertificatePrefix).crt" )
    If($certIficate) {
        $certIficate | Import-CertIficate -CertStoreLocation cert:\CurrentUser\Root
    }
    else {
        -Message "An error occurred while generating the certIficate: certs\$($CertificatePrefix).crt" -Category ReadError
    }

    # openssl req -text -noout -in nginx-proxy-app.com.csr # DEBUG 

    # write hosts

    Write-Host "Adding hosts to $HostsFile" -ForegroundColor "Yellow"

    Add-Host "myapp.nginx-proxy-app.com"
    Print-Hosts

    Write-Host "Completed" -ForegroundColor "Green"
}


# #############################################################################
# Adds a host name
#
Function Add-Host([string]$hostname) {
    Remove-Host $hostname
    $HostsIP + "`t`t" + $hostname | Out-File -encoding ASCII -append $HostsFile
}


# #############################################################################
# Removes all host names matching $HostsDomain variable (*.domain.com)
#
Function Remove-Host([string]$hostname) {
    $c = Get-Content $HostsFile
    $newLines = @()

    foreach ($line in $c) {
        $bits = [regex]::Split($line, "\t+")
        if ($bits.count -Eq 2) {
            if ($bits[1] -Ne $hostname) {
                $newLines += $line
            }
        } else {
            $newLines += $line
        }
    }

    # Write file
    Clear-Content $HostsFile
    foreach ($line in $newLines) {
        $line | Out-File -encoding ASCII -append $HostsFile
    }
}


# #############################################################################
# Prints hosts
#
Function Print-Hosts() {
    $content = Get-Content $HostsFile

    foreach ($line in $content) {
        $bits = [regex]::Split($line, "\t+")
        if ($bits.count -eq 2) {
            Write-Host $bits[0] `t`t $bits[1]
        }
    }
}


# #############################################################################
# Switch arguments
#
If ($Clean) {
    CleanAll
}
ElseIf ($Compose) {
    Compose
}
ElseIf ($ComposeForDebug) {
    $env:REMOTE_DEBUGGING = "enabled"
    Compose
}
ElseIf ($Setup) {
    SetupProxy
}

# #############################################################################
