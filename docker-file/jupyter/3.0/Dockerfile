FROM r.mayishangshu.cn:82/public/jupyterlab:1.0

USER root

# ============================================================
# 系统层:git CLI + Node.js 20 LTS(预编译二进制,跟 jupyter-ai 一致)
# - apt 默认 nodejs 12 太老,jupyterlab 3.6 编译需要 node 14+,
#   且 lib0 等 npm 包要 node 14+(会报 engine incompatible)
# - 直接从 nodejs.org 下预编译二进制,免 nodesource 拉慢
# - 装到 /opt/node20,符号链接到 /usr/local/bin
# ============================================================
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates git openssh-client && \
    cd /tmp && \
    curl -fsSL https://nodejs.org/dist/v20.16.0/node-v20.16.0-linux-x64.tar.gz -o node20.tar.gz && \
    tar xzf node20.tar.gz && \
    mv node-v20.16.0-linux-x64 /opt/node20 && \
    ln -sf /opt/node20/bin/node /usr/local/bin/node && \
    ln -sf /opt/node20/bin/npm /usr/local/bin/npm && \
    ln -sf /opt/node20/bin/npx /usr/local/bin/npx && \
    rm -rf /tmp/node20.tar.gz /tmp/node-v20.16.0-linux-x64 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# 升级 jupyterlab 到 3.x(为 jupyterlab-git 0.50.2 铺路)
# 基础镜像 public/jupyterlab:1.0 大概率是 jupyterlab 1.x,装不上新版扩展
# 钉到 3.6.x 是因为它对 Python 3.7 仍然友好,扩展兼容性最稳
# 若实测发现基础镜像已是 3.5+,这一步会变成 noop
# ============================================================
RUN pip3 install --no-cache-dir \
        -i https://pypi.org/simple/ \
        "jupyterlab>=3.6,<4.0"

# ============================================================
# 安装 jupyterlab-git 扩展(钉 0.44.0 = 兼容 jupyterlab 3.6.x 的最新版)
# 历史:0.41.0 注册了 Git 菜单但没注册左侧栏图标和 Open Git Panel 命令,Git 面板空
#      0.44.0 是 jupyterlab 3.x 兼容系列的末位,左侧栏图标和命令面板齐全
# 若实测后基础镜像已是 jupyterlab 4.x,可放宽到 0.51+
# ============================================================
RUN pip3 install --no-cache-dir \
        -i https://pypi.org/simple/ \
        "jupyterlab-git==0.44.0"

# ============================================================
# 编译 JupyterLab 前端 assets(关键!)
# pip install jupyterlab-git 只装后端 Python 包 + npm 元数据,
# 浏览器侧的按钮(Commit/Push/Pull 等)需要 `jupyter lab build`
# 编译 webpack 产物才会出现。
# 不做这步,Git 面板里只有 Help,没有操作按钮。
# ============================================================
RUN jupyter lab build && \
    npm cache clean --force && \
    rm -rf /root/.npm /tmp/*

# ============================================================
# 沿用 2.0 的科学栈
# ============================================================
RUN pip3 install --no-cache-dir \
        -i https://pypi.org/simple/ \
        pandas numpy matplotlib scikit-learn

# ============================================================
# 沿用 2.0 的 kaniko(华为云镜像源,避免 gcr.io 超时)
# ============================================================
COPY --from=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/gcr.io/kaniko-project/executor:latest \
     /kaniko/executor /usr/local/bin/kaniko
RUN kaniko version

# ============================================================
# 沿用 2.0 的跨域 / 远程访问配置
# ============================================================
RUN mkdir -p /root/.jupyter && \
    echo "c.ServerApp.ip = '0.0.0.0'"                   >  /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.port = 8888"                       >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_origin = '*'"                >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_remote_access = True"        >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.trust_xheaders = True"             >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.disable_check_xsrf = True"         >> /root/.jupyter/jupyter_lab_config.py

# ============================================================
# 复制启动脚本(注入 git 身份 + 启动 jupyter)
# ============================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 预置 /root/.ssh 目录(运行时挂载 SSH key / ssh-agent socket 用)
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh && \
    mkdir -p /root/work && chmod 755 /root/work

# JupyterLab 默认工作目录(启动时若 clone 了外部仓库会切到仓库目录)
WORKDIR /root/work

EXPOSE 8086
EXPOSE 8888

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
