# 生成 PFX 证书的 PowerShell 脚本

Write-Host "=== PFX 证书生成工具 ===" -ForegroundColor Cyan
Write-Host ""

# 提示用户输入参数
$commonName = Read-Host "请输入通用名称/域名 (默认: localhost)"
if ([string]::IsNullOrWhiteSpace($commonName)) {
    $commonName = "localhost"
}

$daysValidInput = Read-Host "请输入证书有效期(天数) (默认: 365)"
if ([string]::IsNullOrWhiteSpace($daysValidInput)) {
    $daysValid = 365
} else {
    $daysValid = [int]$daysValidInput
}

$password = Read-Host "请输入 PFX 密码 (默认: 1010510)"
if ([string]::IsNullOrWhiteSpace($password)) {
    $password = "1010510"
}

$country = Read-Host "请输入国家代码 (默认: CN)"
if ([string]::IsNullOrWhiteSpace($country)) {
    $country = "CN"
}

# 验证国家代码必须是2个字母
if ($country.Length -ne 2 -or $country -notmatch '^[A-Za-z]{2}$') {
    Write-Host "警告: 国家代码必须是2个字母的标准代码(如CN,US,JP)，将使用默认值 CN" -ForegroundColor Yellow
    $country = "CN"
}

$state = Read-Host "请输入省份 (默认: 空)"
if ([string]::IsNullOrWhiteSpace($state)) {
    $state = ""
}

$locality = Read-Host "请输入城市 (默认: 空)"
if ([string]::IsNullOrWhiteSpace($locality)) {
    $locality = ""
}

$organization = Read-Host "请输入组织名称 (默认: 空)"
if ([string]::IsNullOrWhiteSpace($organization)) {
    $organization = ""
}

$organizationalUnit = Read-Host "请输入部门 (默认: 空)"
if ([string]::IsNullOrWhiteSpace($organizationalUnit)) {
    $organizationalUnit = ""
}



Write-Host ""

# 创建证书子文件夹
$certFolder = Join-Path -Path $PSScriptRoot -ChildPath $commonName
if (Test-Path $certFolder) {
    Write-Host "文件夹 '$commonName' 已存在，将覆盖其中的文件。" -ForegroundColor Yellow
} else {
    New-Item -Path $certFolder -ItemType Directory | Out-Null
    Write-Host "已创建文件夹: $certFolder" -ForegroundColor Green
}

# 输出文件名 (保存在子文件夹中)
$keyFile = Join-Path -Path $certFolder -ChildPath "$commonName.key"
$csrFile = Join-Path -Path $certFolder -ChildPath "$commonName.csr"
$crtFile = Join-Path -Path $certFolder -ChildPath "$commonName.crt"
$pfxFile = Join-Path -Path $certFolder -ChildPath "$commonName.pfx"

Write-Host ""
Write-Host "开始生成证书..." -ForegroundColor Green

# 1. 生成私钥
Write-Host "步骤 1: 生成私钥 ($keyFile)" -ForegroundColor Yellow
openssl genrsa -out $keyFile 2048 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "生成私钥失败!" -ForegroundColor Red
    exit 1
}

# 2. 生成证书签名请求 (CSR)
Write-Host "步骤 2: 生成证书签名请求 ($csrFile)" -ForegroundColor Yellow

# 使用配置文件方式支持中文，避免乱码
$configFile = Join-Path -Path $certFolder -ChildPath "openssl.cnf"
$configContent = @"
[req]
distinguished_name = req_distinguished_name
prompt = no
utf8 = yes
string_mask = utf8only

[req_distinguished_name]
"@

if (![string]::IsNullOrWhiteSpace($country)) {
    $configContent += "`nC = $country"
}
if (![string]::IsNullOrWhiteSpace($state)) {
    $configContent += "`nST = $state"
}
if (![string]::IsNullOrWhiteSpace($locality)) {
    $configContent += "`nL = $locality"
}
if (![string]::IsNullOrWhiteSpace($organization)) {
    $configContent += "`nO = $organization"
}
if (![string]::IsNullOrWhiteSpace($organizationalUnit)) {
    $configContent += "`nOU = $organizationalUnit"
}
if (![string]::IsNullOrWhiteSpace($commonName)) {
    $configContent += "`nCN = $commonName"
} else {
    $configContent += "`nCN = localhost"
}

# 使用 UTF8 编码保存配置文件
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($configFile, $configContent, $utf8NoBom)

openssl req -new -key $keyFile -out $csrFile -config $configFile 2>$null

# 删除临时配置文件
Remove-Item $configFile -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Host "生成 CSR 失败!" -ForegroundColor Red
    exit 1
}

# 3. 生成自签名证书
Write-Host "步骤 3: 生成自签名证书 ($crtFile)" -ForegroundColor Yellow
openssl x509 -req -days $daysValid -in $csrFile -signkey $keyFile -out $crtFile 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "生成证书失败!" -ForegroundColor Red
    exit 1
}

# 4. 将证书和私钥转换为 PFX 格式
Write-Host "步骤 4: 转换为 PFX 格式 ($pfxFile)" -ForegroundColor Yellow
openssl pkcs12 -export -out $pfxFile -inkey $keyFile -in $crtFile -password pass:$password 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "转换为 PFX 失败!" -ForegroundColor Red
    exit 1
}

Write-Host "`n证书生成成功!" -ForegroundColor Green
Write-Host "证书保存位置: $certFolder" -ForegroundColor Cyan
Write-Host "生成的文件:" -ForegroundColor Cyan
Write-Host "  - 私钥: $commonName.key" -ForegroundColor White
Write-Host "  - CSR: $commonName.csr" -ForegroundColor White
Write-Host "  - 证书: $commonName.crt" -ForegroundColor White
Write-Host "  - PFX: $commonName.pfx" -ForegroundColor White
Write-Host "`nPFX 密码: $password" -ForegroundColor Cyan

# 可选: 清理中间文件
# Remove-Item $keyFile, $csrFile, $crtFile