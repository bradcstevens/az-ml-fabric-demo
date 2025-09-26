# Power BI Dashboard Testing Script
# This script validates the deployed dashboard functionality and performance

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory=$false)]
    [string]$DatasetId,

    [Parameter(Mandatory=$false)]
    [int]$TimeoutMinutes = 30,

    [Parameter(Mandatory=$false)]
    [switch]$PerformanceTest,

    [Parameter(Mandatory=$false)]
    [switch]$DetailedOutput
)

Import-Module MicrosoftPowerBIMgmt -Force

# Test configuration
$script:TestResults = @()
$script:FailedTests = 0
$script:PassedTests = 0

# Logging function
function Write-TestLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$TestName = ""
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Cyan" }
        default { "White" }
    }

    $logMessage = "[$timestamp] [$Level] $Message"
    if ($TestName) {
        $logMessage = "[$timestamp] [$Level] [$TestName] $Message"
    }

    Write-Host $logMessage -ForegroundColor $color

    # Store test result
    if ($Level -in @("PASS", "FAIL")) {
        $script:TestResults += @{
            TestName = $TestName
            Result = $Level
            Message = $Message
            Timestamp = $timestamp
        }

        if ($Level -eq "PASS") { $script:PassedTests++ }
        else { $script:FailedTests++ }
    }
}

# Function to test workspace accessibility
function Test-WorkspaceAccess {
    $testName = "Workspace Access"
    Write-TestLog "Testing workspace accessibility" -Level "INFO" -TestName $testName

    try {
        $workspace = Get-PowerBIWorkspace -Id $WorkspaceId
        if ($workspace) {
            Write-TestLog "Workspace accessible: $($workspace.Name)" -Level "PASS" -TestName $testName
            return $workspace
        }
        else {
            Write-TestLog "Workspace not found or not accessible" -Level "FAIL" -TestName $testName
            return $null
        }
    }
    catch {
        Write-TestLog "Failed to access workspace: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
        return $null
    }
}

# Function to test dataset availability
function Test-DatasetAvailability {
    param([string]$WorkspaceId)

    $testName = "Dataset Availability"
    Write-TestLog "Testing dataset availability" -Level "INFO" -TestName $testName

    try {
        $datasets = Get-PowerBIDataset -WorkspaceId $WorkspaceId
        $mlDataset = $datasets | Where-Object { $_.Name -like "*ML_Predictions*" -or $_.Name -like "*ML*" }

        if ($mlDataset) {
            Write-TestLog "ML Predictions dataset found: $($mlDataset.Name)" -Level "PASS" -TestName $testName
            return $mlDataset
        }
        else {
            Write-TestLog "ML Predictions dataset not found" -Level "FAIL" -TestName $testName
            if ($DetailedOutput) {
                Write-TestLog "Available datasets: $($datasets.Name -join ', ')" -Level "INFO" -TestName $testName
            }
            return $null
        }
    }
    catch {
        Write-TestLog "Failed to retrieve datasets: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
        return $null
    }
}

# Function to test report accessibility
function Test-ReportAccess {
    param([string]$WorkspaceId)

    $testName = "Report Access"
    Write-TestLog "Testing report accessibility" -Level "INFO" -TestName $testName

    try {
        $reports = Get-PowerBIReport -WorkspaceId $WorkspaceId
        $mlReport = $reports | Where-Object { $_.Name -like "*ML_Predictions*" -or $_.Name -like "*Dashboard*" }

        if ($mlReport) {
            Write-TestLog "ML Predictions report found: $($mlReport.Name)" -Level "PASS" -TestName $testName
            return $mlReport
        }
        else {
            Write-TestLog "ML Predictions report not found" -Level "FAIL" -TestName $testName
            if ($DetailedOutput) {
                Write-TestLog "Available reports: $($reports.Name -join ', ')" -Level "INFO" -TestName $testName
            }
            return $null
        }
    }
    catch {
        Write-TestLog "Failed to retrieve reports: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
        return $null
    }
}

# Function to test data refresh capability
function Test-DataRefresh {
    param([string]$WorkspaceId, [string]$DatasetId)

    $testName = "Data Refresh"
    Write-TestLog "Testing data refresh capability" -Level "INFO" -TestName $testName

    try {
        # Get current refresh history
        $refreshes = Invoke-PowerBIRestMethod -Url "groups/$WorkspaceId/datasets/$DatasetId/refreshes" -Method GET | ConvertFrom-Json

        if ($refreshes.value -and $refreshes.value.Count -gt 0) {
            $latestRefresh = $refreshes.value[0]
            $refreshStatus = $latestRefresh.status
            $refreshTime = $latestRefresh.endTime

            if ($refreshStatus -eq "Completed") {
                Write-TestLog "Latest refresh completed successfully at $refreshTime" -Level "PASS" -TestName $testName
            }
            elseif ($refreshStatus -eq "Failed") {
                Write-TestLog "Latest refresh failed at $refreshTime" -Level "FAIL" -TestName $testName
            }
            else {
                Write-TestLog "Refresh in progress or unknown status: $refreshStatus" -Level "WARNING" -TestName $testName
            }
        }
        else {
            Write-TestLog "No refresh history found - triggering test refresh" -Level "INFO" -TestName $testName

            # Trigger a refresh for testing
            $refreshResult = Invoke-PowerBIRestMethod -Url "groups/$WorkspaceId/datasets/$DatasetId/refreshes" -Method POST

            if ($refreshResult) {
                Write-TestLog "Test refresh initiated successfully" -Level "PASS" -TestName $testName
            }
            else {
                Write-TestLog "Failed to initiate test refresh" -Level "FAIL" -TestName $testName
            }
        }
    }
    catch {
        Write-TestLog "Failed to test data refresh: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
    }
}

# Function to test data source connections
function Test-DataSourceConnections {
    param([string]$WorkspaceId, [string]$DatasetId)

    $testName = "Data Source Connections"
    Write-TestLog "Testing data source connections" -Level "INFO" -TestName $testName

    try {
        $dataSources = Get-PowerBIDatasource -WorkspaceId $WorkspaceId -DatasetId $DatasetId

        if ($dataSources -and $dataSources.Count -gt 0) {
            $oneLakeSource = $dataSources | Where-Object { $_.DatasourceType -eq "OneLake" -or $_.ConnectionString -like "*onelake*" }

            if ($oneLakeSource) {
                Write-TestLog "OneLake data source connection found and configured" -Level "PASS" -TestName $testName
            }
            else {
                Write-TestLog "OneLake data source not found or not configured" -Level "FAIL" -TestName $testName
                if ($DetailedOutput) {
                    Write-TestLog "Available data sources: $($dataSources.DatasourceType -join ', ')" -Level "INFO" -TestName $testName
                }
            }
        }
        else {
            Write-TestLog "No data sources found for dataset" -Level "FAIL" -TestName $testName
        }
    }
    catch {
        Write-TestLog "Failed to test data source connections: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
    }
}

# Function to test dashboard performance
function Test-DashboardPerformance {
    param([string]$WorkspaceId, [string]$ReportId)

    $testName = "Dashboard Performance"

    if (-not $PerformanceTest) {
        Write-TestLog "Performance test skipped (use -PerformanceTest to enable)" -Level "INFO" -TestName $testName
        return
    }

    Write-TestLog "Testing dashboard performance" -Level "INFO" -TestName $testName

    try {
        # This is a simplified performance test
        # In a real scenario, you would use Power BI REST API to get query performance metrics

        $startTime = Get-Date

        # Simulate dashboard access test
        $reportInfo = Invoke-PowerBIRestMethod -Url "groups/$WorkspaceId/reports/$ReportId" -Method GET | ConvertFrom-Json

        $endTime = Get-Date
        $responseTime = ($endTime - $startTime).TotalSeconds

        if ($responseTime -lt 5) {
            Write-TestLog "Dashboard response time acceptable: $([math]::Round($responseTime, 2)) seconds" -Level "PASS" -TestName $testName
        }
        elseif ($responseTime -lt 10) {
            Write-TestLog "Dashboard response time marginal: $([math]::Round($responseTime, 2)) seconds" -Level "WARNING" -TestName $testName
        }
        else {
            Write-TestLog "Dashboard response time poor: $([math]::Round($responseTime, 2)) seconds" -Level "FAIL" -TestName $testName
        }
    }
    catch {
        Write-TestLog "Failed to test dashboard performance: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
    }
}

# Function to test scheduled refresh configuration
function Test-RefreshSchedule {
    param([string]$WorkspaceId, [string]$DatasetId)

    $testName = "Refresh Schedule"
    Write-TestLog "Testing refresh schedule configuration" -Level "INFO" -TestName $testName

    try {
        $refreshSchedule = Invoke-PowerBIRestMethod -Url "groups/$WorkspaceId/datasets/$DatasetId/refreshSchedule" -Method GET | ConvertFrom-Json

        if ($refreshSchedule) {
            if ($refreshSchedule.enabled) {
                Write-TestLog "Scheduled refresh is enabled" -Level "PASS" -TestName $testName
                if ($DetailedOutput) {
                    Write-TestLog "Refresh frequency: $($refreshSchedule.frequency)" -Level "INFO" -TestName $testName
                    Write-TestLog "Refresh times: $($refreshSchedule.times -join ', ')" -Level "INFO" -TestName $testName
                }
            }
            else {
                Write-TestLog "Scheduled refresh is disabled" -Level "WARNING" -TestName $testName
            }
        }
        else {
            Write-TestLog "No refresh schedule configured" -Level "FAIL" -TestName $testName
        }
    }
    catch {
        Write-TestLog "Failed to test refresh schedule: $($_.Exception.Message)" -Level "FAIL" -TestName $testName
    }
}

# Function to generate test report
function Generate-TestReport {
    Write-Host "`n" -NoNewline
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host "Power BI Dashboard Test Results" -ForegroundColor Yellow
    Write-Host "=" * 60 -ForegroundColor Yellow

    Write-Host "Total Tests: $($script:PassedTests + $script:FailedTests)" -ForegroundColor White
    Write-Host "Passed: $script:PassedTests" -ForegroundColor Green
    Write-Host "Failed: $script:FailedTests" -ForegroundColor Red
    Write-Host "Success Rate: $([math]::Round(($script:PassedTests / ($script:PassedTests + $script:FailedTests)) * 100, 1))%" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Yellow" })

    Write-Host "`nDetailed Results:" -ForegroundColor Yellow
    Write-Host "-" * 40 -ForegroundColor Yellow

    foreach ($result in $script:TestResults) {
        $status = if ($result.Result -eq "PASS") { "✅" } else { "❌" }
        $color = if ($result.Result -eq "PASS") { "Green" } else { "Red" }
        Write-Host "$status $($result.TestName): $($result.Message)" -ForegroundColor $color
    }

    # Export detailed results to JSON
    $reportPath = "test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $reportData = @{
        TestSummary = @{
            TotalTests = $script:PassedTests + $script:FailedTests
            PassedTests = $script:PassedTests
            FailedTests = $script:FailedTests
            SuccessRate = [math]::Round(($script:PassedTests / ($script:PassedTests + $script:FailedTests)) * 100, 1)
            ExecutionTime = Get-Date
        }
        TestResults = $script:TestResults
    }

    $reportData | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportPath
    Write-Host "`nDetailed test report saved to: $reportPath" -ForegroundColor Cyan

    return ($script:FailedTests -eq 0)
}

# Main test execution
function Start-DashboardTests {
    Write-Host "Starting Power BI Dashboard Tests" -ForegroundColor Yellow
    Write-Host "Workspace ID: $WorkspaceId" -ForegroundColor Cyan
    Write-Host "Timeout: $TimeoutMinutes minutes" -ForegroundColor Cyan

    try {
        # Authenticate with Power BI
        $currentUser = Get-PowerBIAccessToken -AsString
        if (-not $currentUser) {
            Write-Host "Power BI authentication required. Please sign in..." -ForegroundColor Yellow
            Connect-PowerBIServiceAccount
        }

        # Test 1: Workspace Access
        $workspace = Test-WorkspaceAccess
        if (-not $workspace) { return $false }

        # Test 2: Dataset Availability
        $dataset = Test-DatasetAvailability -WorkspaceId $WorkspaceId
        if ($dataset -and -not $DatasetId) {
            $DatasetId = $dataset.Id
        }

        # Test 3: Report Access
        $report = Test-ReportAccess -WorkspaceId $WorkspaceId

        # Test 4: Data Source Connections
        if ($DatasetId) {
            Test-DataSourceConnections -WorkspaceId $WorkspaceId -DatasetId $DatasetId
        }

        # Test 5: Data Refresh
        if ($DatasetId) {
            Test-DataRefresh -WorkspaceId $WorkspaceId -DatasetId $DatasetId
        }

        # Test 6: Refresh Schedule
        if ($DatasetId) {
            Test-RefreshSchedule -WorkspaceId $WorkspaceId -DatasetId $DatasetId
        }

        # Test 7: Performance
        if ($report) {
            Test-DashboardPerformance -WorkspaceId $WorkspaceId -ReportId $report.Id
        }

        # Generate final report
        return Generate-TestReport
    }
    catch {
        Write-Host "Test execution failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Execute tests
$testSuccess = Start-DashboardTests

# Exit with appropriate code
if ($testSuccess) {
    Write-Host "`n🎉 All tests passed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n⚠️ Some tests failed. Please review the results above." -ForegroundColor Red
    exit 1
}