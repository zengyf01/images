FROM r.mayishangshu.cn:82/public/jupyterlab:1.0

# 安装 Python 依赖
RUN pip3 install \
    secretflow==1.10.0b0 \
    ray[default] \
    uvicorn \
    gradio \
    -i https://pypi.org/simple/ \
    --no-cache-dir

# ---------- 复制 kaniko（使用华为云镜像，避免 gcr.io 超时） ----------
COPY --from=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/kaniko
RUN kaniko version

# ---------- 配置 Jupyter 跨域和远程访问 ----------
RUN mkdir -p /root/.jupyter && \
    echo "c.ServerApp.ip = '0.0.0.0'"                   >  /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.port = 8888"                       >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_origin = '*'"                >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.allow_remote_access = True"        >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.trust_xheaders = True"             >> /root/.jupyter/jupyter_lab_config.py && \
    echo "c.ServerApp.disable_check_xsrf = True"         >> /root/.jupyter/jupyter_lab_config.py

EXPOSE 8086
EXPOSE 8888

# ---------- 容器启动命令 ----------
CMD ["jupyter", "lab", "--config=/root/.jupyter/jupyter_lab_config.py", "--allow-root", "--no-browser"]