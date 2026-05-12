$configFile = Join-Path $env:USERPROFILE ".ssh\config"
$configContent = @"

Host loganalyzer-bastion
  HostName 13.212.251.190
  User ubuntu
  IdentityFile "~/.ssh/loganalyzer-key.pem"
  StrictHostKeyChecking no

Host loganalyzer-master
  HostName 10.0.10.83
  User ubuntu
  IdentityFile "~/.ssh/loganalyzer-key.pem"
  ProxyJump loganalyzer-bastion
  StrictHostKeyChecking no

Host loganalyzer-worker1
  HostName 10.0.10.116
  User ubuntu
  IdentityFile "~/.ssh/loganalyzer-key.pem"
  ProxyJump loganalyzer-bastion
  StrictHostKeyChecking no

Host loganalyzer-worker2
  HostName 10.0.10.182
  User ubuntu
  IdentityFile "~/.ssh/loganalyzer-key.pem"
  ProxyJump loganalyzer-bastion
  StrictHostKeyChecking no
"@

Add-Content -Path $configFile -Value $configContent
