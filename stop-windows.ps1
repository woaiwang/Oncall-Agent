# 设置输出编码为 UTF-8，确保中文字符正确显示
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "====================================" -ForegroundColor Red
Write-Host "停止 SuperBizAgent 服务" -ForegroundColor Red
Write-Host "====================================" -ForegroundColor Red
Write-Host ""

# [1/4] 停止 FastAPI 服务
Write-Host "[1/4] 停止 FastAPI 服务..."
# PowerShell 的 Get-Process 可以更精确地找到由 Start-Process 启动的进程
# 我们通过窗口标题来查找
$fastapiProcess = Get-Process | Where-Object { $_.MainWindowTitle -like "SuperBizAgent API*" }
if ($fastapiProcess) {
    Stop-Process -Id $fastapiProcess.Id -Force
    Write-Host "[成功] FastAPI 服务已停止" -ForegroundColor Green
} else {
    Write-Host "[信息] FastAPI 服务未运行或已停止" -ForegroundColor Yellow
}
Write-Host ""

# [2/4] 停止 CLS MCP 服务
Write-Host "[2/4] 停止 CLS MCP 服务..."
$clsProcess = Get-Process | Where-Object { $_.MainWindowTitle -like "CLS MCP Server*" }
if ($clsProcess) {
    Stop-Process -Id $clsProcess.Id -Force
    Write-Host "[成功] CLS MCP 服务已停止" -ForegroundColor Green
} else {
    Write-Host "[信息] CLS MCP 服务未运行或已停止" -ForegroundColor Yellow
}
Write-Host ""

# [3/4] 停止 Monitor MCP 服务
Write-Host "[3/4] 停止 Monitor MCP 服务..."
$monitorProcess = Get-Process | Where-Object { $_.MainWindowTitle -like "Monitor MCP Server*" }
if ($monitorProcess) {
    Stop-Process -Id $monitorProcess.Id -Force
    Write-Host "[成功] Monitor MCP 服务已停止" -ForegroundColor Green
} else {
    Write-Host "[信息] Monitor MCP 服务未运行或已停止" -ForegroundColor Yellow
}
Write-Host ""

# [4/4] 停止 Docker 容器
Write-Host "[4/4] 停止 Milvus 容器..."
$milvusRunning = docker ps --format "{{.Names}}" | Select-String "milvus"
if ($milvusRunning) {
    docker compose -f vector-database.yml down
    if ($?) {
        Write-Host "[成功] Milvus 容器已停止" -ForegroundColor Green
    } else {
        Write-Host "[错误] Docker 容器停止失败" -ForegroundColor Red
    }
} else {
    Write-Host "[信息] Milvus 容器未运行" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "====================================" -ForegroundColor Red
Write-Host "所有服务已停止！" -ForegroundColor Red
Write-Host "====================================" -ForegroundColor Red
Write-Host ""
Write-Host "提示:" -ForegroundColor Cyan
Write-Host "  - 如需完全清理 Docker 数据卷，运行:"
Write-Host "    docker compose -f vector-database.yml down -v"
Write-Host ""
pause