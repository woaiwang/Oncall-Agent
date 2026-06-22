"""重排服务（Reranker）— 基于阿里云百炼 DashScope gte-rerank 模型

对向量检索的初检结果做精确语义重排。核心区别：

  Bi-Encoder（向量检索）：query 和 doc 各自独立编码为向量，用余弦/L2 距离
                          比较 → 速度快但语义理解粗糙
  Cross-Encoder（重排）：  query 和 doc 拼接后联合编码，能捕捉细粒度语义交互
                          → 更准确但更慢 → 只对初检的 top-K 候选做

流程：
  用户Query → Milvus初检(候选池) → gte-rerank精排 → 取top_n → 返回

参考：https://help.aliyun.com/zh/model-studio/rerank
"""

from typing import List, Tuple

import dashscope
from dashscope import TextReRank
from langchain_core.documents import Document
from loguru import logger

from app.config import config


class RerankerService:
    """重排服务 — 调用百炼 gte-rerank API 做语义重排

    注意：不降级。重排失败直接抛异常，由上游（retrieve_knowledge 工具
    的 try/except）统一捕获并返回错误信息给 LLM。
    """

    def __init__(self):
        self.enabled = config.rerank_enabled
        self.model_name = config.rerank_model
        self.top_n = config.rerank_top_n

        if self.enabled:
            dashscope.api_key = config.dashscope_api_key
            logger.info(
                f"重排服务就绪: model={self.model_name}, "
                f"top_n={self.top_n}, retrieval_k={config.rerank_retrieval_k}"
            )
        else:
            logger.info("重排服务已禁用 (RERANK_ENABLED=False)")

    def rerank(
        self,
        query: str,
        documents: List[Document],
    ) -> List[Document]:
        """对文档列表重排，返回按语义相关性降序排列的 top_n 文档

        Args:
            query: 用户查询文本
            documents: Milvus 初检返回的候选文档列表

        Returns:
            List[Document]: 重排后的 top_n 文档，按相关性分数降序

        Raises:
            RuntimeError: API 调用失败时直接抛出
        """
        # 无需重排的短路场景
        if len(documents) <= self.top_n:
            logger.debug(
                f"文档数({len(documents)}) ≤ top_n({self.top_n})，跳过重排"
            )
            return documents

        if not documents:
            return documents

        # 提取文档纯文本
        doc_texts = [doc.page_content for doc in documents]

        # 调用百炼重排 API
        response = TextReRank.call(
            model=self.model_name,
            query=query,
            documents=doc_texts,
            top_n=self.top_n,
            return_documents=False,  # 不需要原文，用 index 映射回 Document
            api_key=config.dashscope_api_key,
        )

        if response.status_code != 200:
            raise RuntimeError(
                f"重排API调用失败: status={response.status_code}, "
                f"code={response.code}, message={response.message}"
            )

        # 按 API 返回的 index 重新排列文档
        # response.output.results 已按相关性降序排列
        reranked_docs = [documents[result.index] for result in response.output.results]

        scores = [f"{result.relevance_score:.4f}" for result in response.output.results]
        logger.info(
            f"重排完成: {len(documents)} → {len(reranked_docs)} 文档, "
            f"分数: {scores}"
        )

        return reranked_docs

    def rerank_with_scores(
        self,
        query: str,
        documents: List[Document],
    ) -> List[Tuple[Document, float]]:
        """重排并返回带分数的结果（供调试和分析）

        Args:
            query: 用户查询文本
            documents: 候选文档列表

        Returns:
            List[Tuple[Document, float]]: (文档, 相关性分数)，按分数降序

        Raises:
            RuntimeError: API 调用失败时直接抛出
        """
        if not documents:
            return []

        doc_texts = [doc.page_content for doc in documents]

        response = TextReRank.call(
            model=self.model_name,
            query=query,
            documents=doc_texts,
            top_n=self.top_n,
            return_documents=False,
            api_key=config.dashscope_api_key,
        )

        if response.status_code != 200:
            raise RuntimeError(
                f"重排API调用失败: status={response.status_code}, "
                f"code={response.code}, message={response.message}"
            )

        return [
            (documents[result.index], result.relevance_score)
            for result in response.output.results
        ]


# 全局单例
reranker_service = RerankerService()
