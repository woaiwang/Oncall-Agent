# 设置输出编码为 UTF-8，确保中文字符正确显示
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "====================================" -ForegroundColor Green
Write-Host "快速启动 SuperBizAgent 服务" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host ""

# 假设虚拟环境已存在，直接定义 Python 命令路径
$pythonCmd = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $pythonCmd)) {
    Write-Host "[错误] 虚拟环境 '.\.venv\Scripts\python.exe' 不存在。" -ForegroundColor Red
    Write-Host "[提示] 请先运行完整的安装脚本 start-windows.ps1。" -ForegroundColor Yellow
    pause
    exit
}

# [1/4] 启动 Milvus 向量数据库
Write-Host "[1/4] 启动 Milvus 向量数据库..."
$milvusRunning = docker ps --format "{{.Names}}" | Select-String "milvus-standalone"
if ($milvusRunning) {
    Write-Host "[信息] Milvus 容器已在运行。"
} else {
    docker compose -f vector-database.yml up -d
    if (-not $?) { Write-Host "[错误] Docker 启动失败，请确保 Docker Desktop 已启动。" -ForegroundColor Red; pause; exit 1 }
    Write-Host "[信息] 等待 Milvus 启动（10秒）..."
    Start-Sleep -Seconds 10
}
Write-Host "[成功] Milvus 数据库就绪。" -ForegroundColor Green
Write-Host ""

# [2/4] 启动 CLS MCP 服务
Write-Host "[2/4] 启动 CLS MCP 服务..."
Start-Process -FilePath $pythonCmd -ArgumentList "mcp_servers/cls_server.py" -WindowStyle Minimized
Start-Sleep -Seconds 2
Write-Host "[成功] CLS MCP 服务已启动。" -ForegroundColor Green
Write-Host ""

# [3/4] 启动 Monitor MCP 服务
Write-Host "[3/4] 启动 Monitor MCP 服务..."
Start-Process -FilePath $pythonCmd -ArgumentList "mcp_servers/monitor_server.py" -WindowStyle Minimized
Start-Sleep -Seconds 2
Write-Host "[成功] Monitor MCP 服务已启动。" -ForegroundColor Green
Write-Host ""

# [4/4] 启动 FastAPI 服务
Write-Host "[4/4] 启动 FastAPI 服务..."
Start-Process -FilePath $pythonCmd -ArgumentList "-m uvicorn app.main:app --host 0.0.0.0 --port 9900" -PassThru -WindowStyle Normal
Write-Host "[信息] 等待服务启动（5秒）..."
Start-Sleep -Seconds 5
Write-Host ""

# 检查服务状态
Write-Host "[信息] 检查服务状态..."
try {
    $response = Invoke-WebRequest -Uri http://localhost:9900/health -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "[成功] FastAPI 服务运行正常。" -ForegroundColor Green
    }
} catch {
    Write-Host "[警告] 服务可能还未完全启动，请稍等片刻访问。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host "服务启动完成！" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host "Web 界面: http://localhost:9900"
Write-Host "API 文档: http://localhost:9900/docs"
Write-Host "====================================" -ForegroundColor Green
pause