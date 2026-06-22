# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SuperBizAgent** — 企业级智能运维助手。两条核心链路：RAG 知识库对话和 AIOps Plan-Execute-Replan 自动故障诊断。技术栈：FastAPI + LangChain/LangGraph + 阿里云百炼 DashScope（通义千问）+ Milvus 向量数据库 + MCP 协议。

## Essential Commands

```powershell
# 激活虚拟环境
.venv\Scripts\activate

# 安装依赖
uv pip install -e .

# 启动 Docker（Milvus 向量数据库）
docker compose -f vector-database.yml up -d

# 启动主服务（端口 9900）
python -m uvicorn app.main:app --host 0.0.0.0 --port 9900

# 启动 MCP 服务（另开终端）
python mcp_servers/cls_server.py      # CLS 日志查询，端口 8003
python mcp_servers/monitor_server.py  # 监控数据，端口 8004

# 一键启动（Windows）
.\start-windows.bat

# 上传文档到知识库
python -c "import requests, os; [requests.post('http://localhost:9900/api/upload', files={'file': open(f'aiops-docs/{f}', 'rb')}) for f in os.listdir('aiops-docs') if f.endswith('.md')]"
```

## Architecture

### 两条核心业务链路

**RAG 对话**：`POST /api/chat` 或 `/api/chat_stream` → `app/api/chat.py` → `RagAgentService`（`app/services/rag_agent_service.py`）→ LangChain `create_agent()` 自动管理 ReAct 循环。Agent 按需调用工具（知识检索、时间查询、Prometheus 告警、MCP 日志/监控），流式模式通过 SSE 逐字推送。

**AIOps 诊断**：`POST /api/aiops` → `app/api/aiops.py` → `AIOpsService`（`app/services/aiops_service.py`）→ 三节点 LangGraph 状态机：Planner 制定计划 → Executor 逐步执行（LLM + ToolNode）→ Replanner 评估决策（继续/调整/报告）。决策优先级：respond > continue > replan。安全约束：≥8步强制结束，≥5步禁止 replan，新步骤数不超原剩余数。

### RAG 重排流水线（魔改#1）

```
Query → Embedding → Milvus L2检索(候选池9条) → 百炼gte-rerank精排 → 取top_n(3条) → format_docs → 喂LLM
```

重排服务：`app/services/reranker_service.py`，配置在 `app/config.py`（`rerank_*` 字段）。重排失败直接抛异常（不降级），由 `retrieve_knowledge` 工具的 try/except 统一捕获。

### 关键设计模式

- **全局单例**：所有 Service 类（`reranker_service`、`rag_agent_service`、`vector_store_manager` 等）都在模块底部创建全局单例，通过 `from app.services.xxx import xxx` 直接使用
- **配置管理**：`app/config.py` 的 `Settings` 类用 Pydantic Settings 从 `.env` 自动加载，类型安全
- **MCP 协议**：`app/agent/mcp_client.py` 用 `MultiServerMCPClient` 全局单例管理 MCP 连接，内置重试拦截器（指数退避，最多3次）。工具加载失败不阻塞——Agent 降级为仅本地工具运行
- **知识检索**：`retrieve_knowledge` 工具（`app/tools/knowledge_tool.py`）是 RAG 对话和 AIOps Planner 的共用检索入口，改一处两者都受益
- **会话管理**：`MemorySaver` 以 session_id 为 thread_id 做内存级持久化，消息超7条时自动修剪（保留首条 + 最近6条）

### 配置要点

`.env` 文件关键变量：
- `DASHSCOPE_API_KEY` — 百炼 API Key（必填）
- `DASHSCOPE_MODEL=qwen-max` / `RAG_MODEL=qwen-max` — LLM 模型
- `MILVUS_HOST=localhost:19530` — 向量数据库
- `RAG_TOP_K=3` — 不重排时的检索数量
- `RERANK_*` — 重排相关配置（enabled/model/top_n/retrieval_k）

### 重要约束

- `.env` 在 `.gitignore` 中，不能提交。参考 `.env.example` 模板
- Windows CRLF 警告可忽略（Git 的 core.autocrlf）
- MCP 服务需在启动主服务前启动，否则 MCP 工具加载静默失败
- `retrieve_knowledge` 用 `response_format="content_and_artifact"`，内部返回 `(content, docs)` 元组；外部 `ainvoke()` 调用时只返回 content（字符串）
- Milvus ORM API 有 deprecation 警告（PyMilvus 2.x→3.x），不影响功能
