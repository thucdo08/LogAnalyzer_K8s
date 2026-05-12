# save-outputs.ps1 — Run ONCE after "terraform apply" to save all outputs
# Usage (from project root): .\terraform\scripts\save-outputs.ps1
# Then load: . "$env:USERPROFILE\loganalyzer.env.ps1"

$ErrorActionPreference = "Stop"

$TerraformDir = Join-Path $PSScriptRoot ".."
$EnvFile = Join-Path $env:USERPROFILE "loganalyzer.env.ps1"

Write-Host "Reading Terraform outputs from: $TerraformDir" -ForegroundColor Cyan
Push-Location $TerraformDir

try {
    # Verify state exists
    if (-not (Test-Path "terraform.tfstate")) {
        Write-Error "terraform.tfstate not found. Run 'terraform apply' first."
        exit 1
    }

    # Read outputs
    $BASTION_IP  = terraform output -raw bastion_public_ip
    $MASTER_IP   = terraform output -raw k8s_master_private_ip
    $ECR_BACKEND = terraform output -raw ecr_backend_url
    $ECR_FRONTEND= terraform output -raw ecr_frontend_url
    $S3_BUCKET   = terraform output -raw s3_log_archive_bucket
    $WORKER_IPS  = (terraform output -json k8s_worker_private_ips | ConvertFrom-Json) -join " "

    $AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text).Trim()
    $ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.ap-southeast-1.amazonaws.com"
    $SSH_KEY        = Join-Path $env:USERPROFILE ".ssh\loganalyzer-key.pem"

    # Write env file (PowerShell format — use dot-sourcing to load)
    $content = @"
# LogAnalyzer Environment Variables (PowerShell)
# Generated: $(Get-Date)
# Load with: . "`$env:USERPROFILE\loganalyzer.env.ps1"

`$env:AWS_ACCOUNT_ID = "$AWS_ACCOUNT_ID"
`$env:AWS_REGION     = "ap-southeast-1"
`$env:ECR_REGISTRY   = "$ECR_REGISTRY"
`$env:BASTION_IP     = "$BASTION_IP"
`$env:MASTER_IP      = "$MASTER_IP"
`$env:WORKER_IPS     = "$WORKER_IPS"
`$env:ECR_BACKEND    = "$ECR_BACKEND"
`$env:ECR_FRONTEND   = "$ECR_FRONTEND"
`$env:S3_BUCKET      = "$S3_BUCKET"
`$env:SSH_KEY        = "$SSH_KEY"

# Shortcuts (functions)
function ssh-master { ssh loganalyzer-master }
function ssh-bastion { ssh loganalyzer-bastion }
function ssh-worker1 { ssh loganalyzer-worker1 }
function ssh-worker2 { ssh loganalyzer-worker2 }

Write-Host "✅ LogAnalyzer env loaded:" -ForegroundColor Green
Write-Host "   Bastion : `$env:BASTION_IP"
Write-Host "   Master  : `$env:MASTER_IP"
Write-Host "   ECR     : `$env:ECR_REGISTRY"
"@

    $content | Out-File -FilePath $EnvFile -Encoding UTF8

    # --- Update SSH Config dynamically ---
    $sshConfigFile = Join-Path $env:USERPROFILE ".ssh\config"
    $sshConfigContent = @"

Host loganalyzer-bastion
  HostName $BASTION_IP
  User ubuntu
  IdentityFile "$SSH_KEY"
  StrictHostKeyChecking no

Host loganalyzer-master
  HostName $MASTER_IP
  User ubuntu
  IdentityFile "$SSH_KEY"
  ProxyJump loganalyzer-bastion
  StrictHostKeyChecking no
"@
    # Add workers to SSH config
    $workerArray = $WORKER_IPS -split " "
    for ($i = 0; $i -lt $workerArray.Length; $i++) {
        $sshConfigContent += @"

Host loganalyzer-worker$($i + 1)
  HostName $($workerArray[$i])
  User ubuntu
  IdentityFile "$SSH_KEY"
  ProxyJump loganalyzer-bastion
  StrictHostKeyChecking no
"@
    }

    # Backup existing config if it exists
    if (Test-Path $sshConfigFile) {
        # Only backup once a day to avoid spamming
        $backupFile = "$sshConfigFile.bak"
        Copy-Item -Path $sshConfigFile -Destination $backupFile -Force
    }

    $sshConfigContent | Out-File -FilePath $sshConfigFile -Encoding UTF8
    Write-Host "✅ Updated SSH config: $sshConfigFile" -ForegroundColor Green

    Write-Host ""
    Write-Host "✅ Saved to: $EnvFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  Bastion IP : $BASTION_IP"
    Write-Host "  Master IP  : $MASTER_IP"
    Write-Host "  Worker IPs : $WORKER_IPS"
    Write-Host "  ECR Backend: $ECR_BACKEND"
    Write-Host "  S3 Bucket  : $S3_BUCKET"
    Write-Host ""
    Write-Host "Load into current terminal:" -ForegroundColor Cyan
    Write-Host "  . `"$EnvFile`""
    Write-Host ""
    Write-Host "Auto-load every new PowerShell terminal (run once):" -ForegroundColor Cyan
    Write-Host "  Add-Content `$PROFILE `". $EnvFile`""

} finally {
    Pop-Location
}
