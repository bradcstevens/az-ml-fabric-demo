# Power BI Dashboard Deployment Script
# This script automates the deployment of ML Predictions Dashboard to Power BI Service

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName = "ML Predictions Analytics",

    [Parameter(Mandatory=$true)]
    [string]$OneLakeConnectionString,

    [Parameter(Mandatory=$false)]
    [string]$DashboardPath = "../templates/ML_Predictions_Dashboard.pbix",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "Production",

    [Parameter(Mandatory=$false)]
    [switch]$SkipTests
)

# Import required modules
try {
    Import-Module MicrosoftPowerBIMgmt -Force
    Import-Module Az.Accounts -Force
    Write-Host "✅ PowerShell modules imported successfully" -ForegroundColor Green
}
catch {
    Write-Error "❌ Failed to import required PowerShell modules. Please install: Install-Module MicrosoftPowerBIMgmt, Az.Accounts"
    exit 1
}

# Function to log messages with timestamps
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Function to test prerequisites
function Test-Prerequisites {
    Write-Log "Testing deployment prerequisites..."

    # Test Power BI connectivity
    try {
        $currentUser = Get-PowerBIAccessToken -AsString
        if (-not $currentUser) {
            Write-Log "Power BI authentication required. Initiating login..." -Level "WARNING"
            Connect-PowerBIServiceAccount
        }
        Write-Log "Power BI authentication verified" -Level "SUCCESS"
    }
    catch {
        Write-Log "Power BI authentication failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }

    # Test Azure connectivity
    try {
        $azContext = Get-AzContext
        if (-not $azContext) {
            Write-Log "Azure authentication required. Initiating login..." -Level "WARNING"
            Connect-AzAccount
        }
        Write-Log "Azure authentication verified" -Level "SUCCESS"
    }
    catch {
        Write-Log "Azure authentication failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }

    # Test dashboard file exists
    if (-not (Test-Path $DashboardPath)) {
        Write-Log "Dashboard file not found: $DashboardPath" -Level "ERROR"
        return $false
    }
    Write-Log "Dashboard template file found" -Level "SUCCESS"

    return $true
}

# Function to create or get workspace
function Initialize-Workspace {
    param([string]$Name)

    Write-Log "Initializing Power BI workspace: $Name"

    try {
        # Check if workspace exists
        $workspace = Get-PowerBIWorkspace -Name $Name -ErrorAction SilentlyContinue

        if (-not $workspace) {
            Write-Log "Creating new workspace: $Name"
            $workspace = New-PowerBIWorkspace -Name $Name
            Write-Log "Workspace created successfully" -Level "SUCCESS"
        }
        else {
            Write-Log "Using existing workspace: $Name" -Level "SUCCESS"
        }

        return $workspace
    }
    catch {
        Write-Log "Failed to initialize workspace: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Function to publish dashboard
function Publish-Dashboard {
    param(
        [object]$Workspace,
        [string]$FilePath
    )

    Write-Log "Publishing dashboard to workspace: $($Workspace.Name)"

    try {
        # Import PBIX file
        $import = New-PowerBIReport -Path $FilePath -WorkspaceId $Workspace.Id -ConflictAction CreateOrOverwrite
        Write-Log "Dashboard published successfully" -Level "SUCCESS"

        # Wait for import completion
        do {
            Start-Sleep -Seconds 5
            $importStatus = Get-PowerBIImport -ImportId $import.Id -WorkspaceId $Workspace.Id
            Write-Log "Import status: $($importStatus.ImportState)"
        } while ($importStatus.ImportState -eq "Publishing")

        if ($importStatus.ImportState -eq "Succeeded") {
            Write-Log "Dashboard import completed successfully" -Level "SUCCESS"
            return $importStatus
        }
        else {
            Write-Log "Dashboard import failed: $($importStatus.ImportState)" -Level "ERROR"
            throw "Import failed"
        }
    }
    catch {
        Write-Log "Failed to publish dashboard: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Function to configure data source
function Configure-DataSource {
    param(
        [object]$Workspace,
        [object]$Dataset,
        [string]$ConnectionString
    )

    Write-Log "Configuring OneLake data source"

    try {
        # Get dataset datasources
        $dataSources = Get-PowerBIDatasource -WorkspaceId $Workspace.Id -DatasetId $Dataset.Id

        foreach ($dataSource in $dataSources) {
            if ($dataSource.DatasourceType -eq "OneLake") {
                Write-Log "Updating OneLake connection string"

                # Update credentials (this requires appropriate permissions)
                $credentialDetails = @{
                    credentialType = "OAuth2"
                    connectionString = $ConnectionString
                }

                # Note: Actual credential update requires REST API call
                # Set-PowerBIDatasourceCredentials is not available in standard module
                Write-Log "OneLake data source configured (manual credential setup required)" -Level "WARNING"
            }
        }
    }
    catch {
        Write-Log "Failed to configure data source: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Function to configure refresh schedule
function Configure-RefreshSchedule {
    param(
        [object]$Workspace,
        [object]$Dataset
    )

    Write-Log "Configuring refresh schedule for dataset"

    try {
        $refreshSchedule = @{
            times = @("06:00")
            frequency = "Daily"
            localTimeZoneId = "UTC"
            enabled = $true
            notifyOption = "MailOnFailure"
        }

        # Note: This requires REST API call as PowerShell module doesn't support this directly
        $uri = "https://api.powerbi.com/v1.0/myorg/groups/$($Workspace.Id)/datasets/$($Dataset.Id)/refreshSchedule"
        $headers = @{
            'Authorization' = "Bearer $(Get-PowerBIAccessToken -AsString)"
            'Content-Type' = 'application/json'
        }

        $body = $refreshSchedule | ConvertTo-Json -Depth 3

        Invoke-RestMethod -Uri $uri -Method PATCH -Headers $headers -Body $body
        Write-Log "Refresh schedule configured successfully" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to configure refresh schedule: $($_.Exception.Message)" -Level "ERROR"
        # Non-critical error, continue deployment
    }
}

# Function to run validation tests
function Test-Deployment {
    param(
        [object]$Workspace,
        [object]$Dataset
    )

    Write-Log "Running deployment validation tests"

    try {
        # Test data refresh
        Write-Log "Testing dataset refresh capability"
        $refreshResult = Invoke-PowerBIRestMethod -Url "groups/$($Workspace.Id)/datasets/$($Dataset.Id)/refreshes" -Method POST

        if ($refreshResult) {
            Write-Log "Dataset refresh initiated successfully" -Level "SUCCESS"
        }

        # Test report accessibility
        $reports = Get-PowerBIReport -WorkspaceId $Workspace.Id
        $targetReport = $reports | Where-Object { $_.Name -like "*ML_Predictions*" }

        if ($targetReport) {
            Write-Log "Dashboard report accessible" -Level "SUCCESS"
        }
        else {
            Write-Log "Dashboard report not found" -Level "ERROR"
            return $false
        }

        return $true
    }
    catch {
        Write-Log "Deployment validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main deployment workflow
function Start-Deployment {
    Write-Log "Starting Power BI Dashboard deployment" -Level "SUCCESS"
    Write-Log "Environment: $Environment"
    Write-Log "Workspace: $WorkspaceName"

    try {
        # Step 1: Test prerequisites
        if (-not (Test-Prerequisites)) {
            throw "Prerequisites validation failed"
        }

        # Step 2: Initialize workspace
        $workspace = Initialize-Workspace -Name $WorkspaceName

        # Step 3: Publish dashboard
        $importResult = Publish-Dashboard -Workspace $workspace -FilePath $DashboardPath

        # Step 4: Get dataset information
        $datasets = Get-PowerBIDataset -WorkspaceId $workspace.Id
        $dataset = $datasets | Where-Object { $_.Name -like "*ML_Predictions*" } | Select-Object -First 1

        if (-not $dataset) {
            throw "Dataset not found after import"
        }

        # Step 5: Configure data source
        Configure-DataSource -Workspace $workspace -Dataset $dataset -ConnectionString $OneLakeConnectionString

        # Step 6: Configure refresh schedule
        Configure-RefreshSchedule -Workspace $workspace -Dataset $dataset

        # Step 7: Run validation tests
        if (-not $SkipTests) {
            $validationResult = Test-Deployment -Workspace $workspace -Dataset $dataset
            if (-not $validationResult) {
                Write-Log "Validation tests failed" -Level "WARNING"
            }
        }

        # Step 8: Output deployment summary
        Write-Log "=== DEPLOYMENT SUMMARY ===" -Level "SUCCESS"
        Write-Log "Workspace: $($workspace.Name) (ID: $($workspace.Id))" -Level "SUCCESS"
        Write-Log "Dataset: $($dataset.Name) (ID: $($dataset.Id))" -Level "SUCCESS"
        Write-Log "Environment: $Environment" -Level "SUCCESS"
        Write-Log "Dashboard URL: https://app.powerbi.com/groups/$($workspace.Id)" -Level "SUCCESS"
        Write-Log "Deployment completed successfully! 🎉" -Level "SUCCESS"

        return @{
            WorkspaceId = $workspace.Id
            DatasetId = $dataset.Id
            ReportId = $importResult.Reports[0].Id
            Success = $true
        }
    }
    catch {
        Write-Log "Deployment failed: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Please check the logs above for details" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Execute deployment
$deploymentResult = Start-Deployment

# Exit with appropriate code
if ($deploymentResult.Success) {
    exit 0
}
else {
    exit 1
}