# Power BI Environment Setup Script
# This script sets up the required environment and prerequisites for Power BI deployment

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "Development",

    [Parameter(Mandatory=$false)]
    [switch]$InstallModules,

    [Parameter(Mandatory=$false)]
    [switch]$ConfigureCredentials,

    [Parameter(Mandatory=$false)]
    [string]$TenantId,

    [Parameter(Mandatory=$false)]
    [string]$ServicePrincipalId,

    [Parameter(Mandatory=$false)]
    [string]$ServicePrincipalSecret
)

# Function to write setup logs
function Write-SetupLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Function to test PowerShell version
function Test-PowerShellVersion {
    Write-SetupLog "Checking PowerShell version compatibility"

    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-SetupLog "PowerShell version $($psVersion.ToString()) is compatible" -Level "SUCCESS"
        return $true
    }
    else {
        Write-SetupLog "PowerShell version $($psVersion.ToString()) is not supported. Please upgrade to PowerShell 5.1 or later" -Level "ERROR"
        return $false
    }
}

# Function to install required PowerShell modules
function Install-RequiredModules {
    Write-SetupLog "Installing required PowerShell modules"

    $requiredModules = @(
        @{ Name = "MicrosoftPowerBIMgmt"; MinVersion = "1.2.1077" },
        @{ Name = "Az.Accounts"; MinVersion = "2.12.1" },
        @{ Name = "Az.Profile"; MinVersion = "1.0.0" }
    )

    foreach ($module in $requiredModules) {
        try {
            Write-SetupLog "Checking module: $($module.Name)"

            $installedModule = Get-Module -Name $module.Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

            if ($installedModule -and $installedModule.Version -ge [version]$module.MinVersion) {
                Write-SetupLog "Module $($module.Name) v$($installedModule.Version) is already installed" -Level "SUCCESS"
            }
            else {
                Write-SetupLog "Installing module: $($module.Name)"

                if (-not $InstallModules) {
                    Write-SetupLog "Module installation skipped. Use -InstallModules to enable automatic installation" -Level "WARNING"
                    continue
                }

                # Check if running as administrator
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

                if ($isAdmin) {
                    Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -AllowClobber -Scope AllUsers
                }
                else {
                    Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Force -AllowClobber -Scope CurrentUser
                }

                Write-SetupLog "Module $($module.Name) installed successfully" -Level "SUCCESS"
            }
        }
        catch {
            Write-SetupLog "Failed to install module $($module.Name): $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }

    return $true
}

# Function to configure execution policy
function Set-ExecutionPolicyIfNeeded {
    Write-SetupLog "Checking PowerShell execution policy"

    $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser

    if ($executionPolicy -in @("Restricted", "AllSigned")) {
        Write-SetupLog "Current execution policy: $executionPolicy"
        Write-SetupLog "Setting execution policy to RemoteSigned for current user"

        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-SetupLog "Execution policy updated successfully" -Level "SUCCESS"
        }
        catch {
            Write-SetupLog "Failed to update execution policy: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    else {
        Write-SetupLog "Execution policy $executionPolicy is acceptable" -Level "SUCCESS"
    }

    return $true
}

# Function to test Azure connectivity
function Test-AzureConnectivity {
    Write-SetupLog "Testing Azure connectivity"

    try {
        # Test Azure endpoints
        $azureEndpoints = @(
            "https://login.microsoftonline.com",
            "https://management.azure.com",
            "https://api.powerbi.com"
        )

        foreach ($endpoint in $azureEndpoints) {
            $response = Invoke-WebRequest -Uri $endpoint -Method HEAD -TimeoutSec 10 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-SetupLog "Azure endpoint accessible: $endpoint" -Level "SUCCESS"
            }
            else {
                Write-SetupLog "Azure endpoint not accessible: $endpoint (Status: $($response.StatusCode))" -Level "WARNING"
            }
        }

        return $true
    }
    catch {
        Write-SetupLog "Azure connectivity test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Function to configure authentication
function Configure-Authentication {
    Write-SetupLog "Configuring authentication settings"

    if ($ConfigureCredentials -and $TenantId -and $ServicePrincipalId -and $ServicePrincipalSecret) {
        Write-SetupLog "Configuring service principal authentication"

        try {
            # Create secure credential object
            $secureSecret = ConvertTo-SecureString -String $ServicePrincipalSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($ServicePrincipalId, $secureSecret)

            # Store credentials securely (this would typically use Azure Key Vault in production)
            $credentialPath = ".\power-bi-credentials.xml"
            $credential | Export-Clixml -Path $credentialPath

            Write-SetupLog "Service principal credentials configured and stored securely" -Level "SUCCESS"
            Write-SetupLog "Credential file saved to: $credentialPath" -Level "INFO"

            # Test authentication
            Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $credential

            Write-SetupLog "Service principal authentication test successful" -Level "SUCCESS"
        }
        catch {
            Write-SetupLog "Failed to configure service principal authentication: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    else {
        Write-SetupLog "Interactive authentication will be used (service principal not configured)" -Level "INFO"
    }

    return $true
}

# Function to create environment configuration file
function Create-EnvironmentConfig {
    Write-SetupLog "Creating environment configuration file"

    $configData = @{
        Environment = $Environment
        PowerBI = @{
            TenantId = $TenantId
            ServicePrincipalConfigured = ($null -ne $ServicePrincipalId)
            DefaultWorkspace = "ML Predictions Analytics"
            ApiBaseUrl = "https://api.powerbi.com/v1.0/myorg"
        }
        Azure = @{
            TenantId = $TenantId
            SubscriptionId = ""  # To be filled in during actual deployment
            ResourceGroup = "ml-predictions-rg"
        }
        OneLake = @{
            WorkspaceUrl = "https://onelake.dfs.fabric.microsoft.com/"
            LakehouseName = "ml-predictions-lakehouse"
        }
        Deployment = @{
            TimeoutMinutes = 30
            RetryAttempts = 3
            EnableDetailedLogging = $true
            BackupBeforeDeployment = $true
        }
        CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        CreatedBy = $env:USERNAME
    }

    $configPath = ".\environment-config-$Environment.json"

    try {
        $configData | ConvertTo-Json -Depth 4 | Out-File -FilePath $configPath -Encoding UTF8
        Write-SetupLog "Environment configuration saved to: $configPath" -Level "SUCCESS"
        return $configPath
    }
    catch {
        Write-SetupLog "Failed to create environment configuration: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Function to validate setup
function Test-EnvironmentSetup {
    Write-SetupLog "Validating environment setup"

    $validationResults = @()

    # Test 1: PowerShell modules
    try {
        Import-Module MicrosoftPowerBIMgmt -Force
        Import-Module Az.Accounts -Force
        $validationResults += @{ Test = "PowerShell Modules"; Result = "PASS" }
        Write-SetupLog "PowerShell modules validation: PASS" -Level "SUCCESS"
    }
    catch {
        $validationResults += @{ Test = "PowerShell Modules"; Result = "FAIL"; Error = $_.Exception.Message }
        Write-SetupLog "PowerShell modules validation: FAIL" -Level "ERROR"
    }

    # Test 2: Network connectivity
    try {
        $testResult = Test-NetConnection -ComputerName "api.powerbi.com" -Port 443 -InformationLevel Quiet
        if ($testResult) {
            $validationResults += @{ Test = "Network Connectivity"; Result = "PASS" }
            Write-SetupLog "Network connectivity validation: PASS" -Level "SUCCESS"
        }
        else {
            $validationResults += @{ Test = "Network Connectivity"; Result = "FAIL" }
            Write-SetupLog "Network connectivity validation: FAIL" -Level "ERROR"
        }
    }
    catch {
        $validationResults += @{ Test = "Network Connectivity"; Result = "FAIL"; Error = $_.Exception.Message }
        Write-SetupLog "Network connectivity validation: FAIL" -Level "ERROR"
    }

    # Test 3: File permissions
    try {
        $testFile = ".\permission-test.tmp"
        "test" | Out-File -FilePath $testFile
        Remove-Item -Path $testFile -Force
        $validationResults += @{ Test = "File Permissions"; Result = "PASS" }
        Write-SetupLog "File permissions validation: PASS" -Level "SUCCESS"
    }
    catch {
        $validationResults += @{ Test = "File Permissions"; Result = "FAIL"; Error = $_.Exception.Message }
        Write-SetupLog "File permissions validation: FAIL" -Level "ERROR"
    }

    return $validationResults
}

# Function to generate setup summary
function Generate-SetupSummary {
    param([array]$ValidationResults)

    Write-Host "`n" -NoNewline
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host "Power BI Environment Setup Summary" -ForegroundColor Yellow
    Write-Host "=" * 60 -ForegroundColor Yellow

    Write-Host "Environment: $Environment" -ForegroundColor Cyan
    Write-Host "Setup Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "User: $env:USERNAME" -ForegroundColor Cyan

    Write-Host "`nValidation Results:" -ForegroundColor Yellow
    Write-Host "-" * 30 -ForegroundColor Yellow

    $passedTests = 0
    $failedTests = 0

    foreach ($result in $ValidationResults) {
        $status = if ($result.Result -eq "PASS") { "✅" } else { "❌" }
        $color = if ($result.Result -eq "PASS") { "Green" } else { "Red" }

        Write-Host "$status $($result.Test)" -ForegroundColor $color

        if ($result.Result -eq "PASS") { $passedTests++ }
        else { $failedTests++ }

        if ($result.Error) {
            Write-Host "   Error: $($result.Error)" -ForegroundColor Red
        }
    }

    Write-Host "`nSummary:" -ForegroundColor Yellow
    Write-Host "Passed: $passedTests" -ForegroundColor Green
    Write-Host "Failed: $failedTests" -ForegroundColor Red

    if ($failedTests -eq 0) {
        Write-Host "`n🎉 Environment setup completed successfully!" -ForegroundColor Green
        Write-Host "You can now run the deployment script." -ForegroundColor Green
    }
    else {
        Write-Host "`n⚠️ Environment setup completed with issues." -ForegroundColor Yellow
        Write-Host "Please resolve the failed validations before proceeding." -ForegroundColor Yellow
    }

    return ($failedTests -eq 0)
}

# Main setup function
function Start-EnvironmentSetup {
    Write-SetupLog "Starting Power BI Environment Setup" -Level "SUCCESS"
    Write-SetupLog "Environment: $Environment"

    try {
        # Step 1: Test PowerShell version
        if (-not (Test-PowerShellVersion)) {
            throw "PowerShell version compatibility check failed"
        }

        # Step 2: Set execution policy
        if (-not (Set-ExecutionPolicyIfNeeded)) {
            throw "Execution policy configuration failed"
        }

        # Step 3: Install required modules
        if (-not (Install-RequiredModules)) {
            throw "PowerShell module installation failed"
        }

        # Step 4: Test Azure connectivity
        if (-not (Test-AzureConnectivity)) {
            Write-SetupLog "Azure connectivity issues detected - deployment may fail" -Level "WARNING"
        }

        # Step 5: Configure authentication
        if (-not (Configure-Authentication)) {
            Write-SetupLog "Authentication configuration issues detected" -Level "WARNING"
        }

        # Step 6: Create environment configuration
        $configPath = Create-EnvironmentConfig
        if (-not $configPath) {
            throw "Environment configuration creation failed"
        }

        # Step 7: Validate setup
        $validationResults = Test-EnvironmentSetup

        # Step 8: Generate summary
        $setupSuccess = Generate-SetupSummary -ValidationResults $validationResults

        return $setupSuccess
    }
    catch {
        Write-SetupLog "Environment setup failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Execute environment setup
$setupResult = Start-EnvironmentSetup

# Exit with appropriate code
if ($setupResult) {
    exit 0
}
else {
    exit 1
}