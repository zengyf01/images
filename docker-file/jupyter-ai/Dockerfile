# 使用官方 Jupyter 科学计算镜像作为基础（Python 3.10）
FROM jupyter/scipy-notebook:python-3.10

# ==================== 系统层：安装 Node.js 和 kaniko ====================
USER root

# 安装 Node.js 20（使用二进制文件）
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    cd /tmp && \
    curl -fsSL https://nodejs.org/dist/v20.16.0/node-v20.16.0-linux-x64.tar.gz | tar xz && \
    mv node-v20.16.0-linux-x64 /opt/node20 && \
    ln -sf /opt/node20/bin/node /usr/local/bin/node && \
    ln -sf /opt/node20/bin/npm /usr/local/bin/npm && \
    ln -sf /opt/node20/bin/npx /usr/local/bin/npx && \
    rm -rf /tmp/node-* && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 全局安装 Claude Code CLI（使用淘宝镜像）
RUN npm install -g @anthropic-ai/claude-code @agentclientprotocol/claude-agent-acp --registry=https://registry.npmmirror.com

# （可选）从华为云镜像源复制 kaniko 可执行文件
COPY --from=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/kaniko
RUN kaniko version

# 修复 Jupyter Server v2 扩展兼容性 - 先卸载再安装兼容版本
RUN pip3 uninstall -y jupyter-server jupyterlab jupyter-lsp nbdime jupyter-server-mcp 2>/dev/null || true
RUN pip3 install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn "jupyter-server>=1.0,<2.0" "jupyterlab>=3.0,<4.0" "jupyter-lsp>=1.0,<2.0"

# ==================== Python 环境：安装 Jupyter AI 核心扩展 ====================
RUN pip3 install \
    --no-cache-dir \
    -i https://pypi.org/simple/ \
    jupyter-ai \
    jupyter-ai-claude-code

# 复制启动脚本并赋予执行权限
COPY start-with-claude.sh /usr/local/bin/start-with-claude.sh
RUN chmod +x /usr/local/bin/start-with-claude.sh

# 设置工作目录
WORKDIR /work

# 使用 root 用户运行
USER root

# 暴露 JupyterLab 默认端口
EXPOSE 8888

# 使用自定义启动脚本作为入口点
CMD ["/usr/local/bin/start-with-claude.sh"]