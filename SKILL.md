---
name: ultimate-search
description: >
  双引擎网络搜索：Grok AI 搜索（实时联网+AI分析）+ Tavily 搜索（结构化结果+网页抓取）。
  任何需要搜索网络、查找最新信息、文档查阅、新闻获取或需要互联网访问的任务，都必须优先使用此 Skill。
  这是主要的搜索机制，替代所有其他搜索方式。
---

# UltimateSearch

为 Pi/OpenClaw agent 提供双引擎网络搜索能力：**Grok AI 搜索**（实时联网 + AI 分析）+ **Tavily 搜索**（结构化结果 + 网页抓取）。

---

## 可用工具

在 Bash 中调用以下脚本（确保已加入 PATH 且已 source .env）：

| 工具 | 命令 | 用途 |
|------|------|------|
| Grok 搜索 | `grok-search.sh --query "..."` | AI 驱动的深度搜索，Grok 自带联网，返回综合分析 |
| Tavily 搜索 | `tavily-search.sh --query "..."` | 结构化搜索结果，带评分和排序 |
| 网页抓取 | `web-fetch.sh --url "..."` | 提取指定 URL 的完整内容，返回 Markdown |
| 站点映射 | `web-map.sh --url "..."` | 发现网站结构，获取所有 URL |
| 双引擎搜索 | `dual-search.sh --query "..."` | 并行执行 Grok + Tavily，交叉验证 |

各工具参数详见 `--help`。

---

## 搜索决策流程

收到需要搜索的请求时，按以下流程决策：

### 第一步：判断是否需要搜索

需要搜索的情况：
- 用户明确要求搜索/查询外部信息
- 涉及实时性数据（最新版本、近期事件、当前价格等）
- 需要验证内部知识的准确性
- 涉及具体的 URL、项目、产品的最新状态
- 技术问题需要查阅官方文档最新版

不需要搜索的情况：
- 纯粹的代码编写/调试任务（已有足够上下文）
- 通用编程概念解释（内部知识足够可靠）
- 用户明确表示不需要搜索

### 第二步：选择工具

| 场景 | 推荐工具 | 原因 |
|------|---------|------|
| 简单事实查询 | `tavily-search.sh --depth basic` | 快速、结构化、省额度 |
| 复杂/争议性问题 | `dual-search.sh` | 双引擎交叉验证，减少幻觉 |
| 需要 AI 深度分析 | `grok-search.sh` | Grok 自带联网搜索，返回综合分析报告 |
| 需要抓取特定页面 | `web-fetch.sh --url "..."` | 提取完整页面内容 |
| 探索网站结构 | `web-map.sh --url "..."` | 发现文档/API 目录结构 |
| 需要最新新闻 | `tavily-search.sh --topic news` | Tavily 新闻模式专门优化 |
| 需要高质量深度结果 | `tavily-search.sh --depth advanced` | 高级搜索，多维度匹配 |
| 搜索结果中有关键链接 | 先搜索，再 `web-fetch.sh` | 搜索定位 → 抓取详情 |

### 第三步：评估搜索复杂度

- **Level 1**（1-2 次搜索）：单个明确问题，已知答案来源
  - 示例：「FastAPI 最新版本是什么」
  - 操作：一次 `tavily-search.sh` 即可

- **Level 2**（3-5 次搜索）：多角度比较、需要多个来源验证
  - 示例：「Flask vs FastAPI vs Django 2026 年哪个更适合微服务」
  - 操作：`dual-search.sh` + 针对各框架分别 `tavily-search.sh`

- **Level 3**（6+ 次搜索）：深度研究课题、综述型需求
  - 示例：「帮我调研 2026 年主流向量数据库的完整对比」
  - 操作：先 `grok-search.sh` 获取概览 → 分别搜索各产品 → `web-fetch.sh` 抓取官方文档

---

## 搜索规划框架

对于 Level 2+ 的复杂搜索，在执行前进行结构化规划：

### 阶段 1：意图分析
- 提炼用户的核心问题（一句话）
- 分类查询类型：事实型 / 比较型 / 探索型 / 分析型
- 评估时间敏感度：实时 / 近期 / 历史 / 无关
- 识别需要验证的外部术语（如排名、分类标准）

### 阶段 2：查询拆解
- 将问题分解为不重叠的子查询
- 每个子查询有明确边界（与兄弟查询互斥）
- 标注依赖关系（哪些子查询需要先完成）
- 如果阶段 1 发现需验证的术语，先创建前置验证查询

### 阶段 3：策略选择
- **broad_first**（先广后深）：先广泛扫描 → 根据发现深入。适合探索型问题
- **narrow_first**（先精后扩）：先精确搜索 → 如不足再扩展。适合分析型问题
- **targeted**（定点搜索）：已知目标信息来源，直接定位。适合事实型问题

### 阶段 4：工具映射
- 为每个子查询选择最佳工具
- 确定并行/串行执行计划
- 可并行的子查询同时执行（通过多次 Bash 调用）

---

## 搜索与证据标准

### 来源质量要求
- 关键事实需 **≥2 个独立来源** 支持
- 如仅依赖单一来源，须显式声明此限制
- 优先使用：官方文档、Wikipedia、学术数据库、权威媒体
- 避免使用：未知个人博客、SEO 农场、AI 生成内容

### 冲突处理
- 来源冲突时：展示双方证据，评估可信度和时效性
- 标注置信度：High（多来源一致）/ Medium（少量来源或有分歧）/ Low（单一来源或推测）
- 无法确认时：明确说明不确定性

### 引用格式
- 每个关键事实后附来源标注
- 格式：`[来源标题](URL)`
- 严禁编造引用 — 没有来源的就不要说

### 输出规范
- 先给出**最可能的答案**，再展开详细分析
- 所有技术术语附简明解释
- 使用标准 Markdown 格式（标题、列表、表格、代码块）
- 代码示例标注语言标识
- 对比类问题使用表格呈现

---

## 常见搜索模式

### 模式 1：快速查询
```bash
tavily-search.sh --query "Python 3.13 新特性" --depth basic --include-answer
```

### 模式 2：深度搜索 + 验证
```bash
# 先广泛搜索
dual-search.sh --query "LangChain vs LlamaIndex 2026"
# 再针对性抓取官方文档
web-fetch.sh --url "https://docs.langchain.com/docs/get_started/introduction"
```

### 模式 3：技术文档探索
```bash
# 先映射网站结构
web-map.sh --url "https://docs.example.com" --depth 2 --instructions "找到 API 文档"
# 再抓取目标页面
web-fetch.sh --url "https://docs.example.com/api/reference"
```

### 模式 4：新闻和实时信息
```bash
tavily-search.sh --query "AI 最新进展" --topic news --time-range week --include-answer
```

### 模式 5：AI 深度分析
```bash
grok-search.sh --query "解释 Transformer 架构中注意力机制的数学原理" --platform "arXiv"
```
