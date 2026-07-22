FROM r.mayishangshu.cn:82/public/jupyterlab:1.0
    
# 安装 Python 依赖
RUN pip3 install \
        -i https://pypi.org/simple/ \
        --no-cache-dir
    
# 从 kaniko 官方镜像复制 kaniko 可执行文件
COPY --from=gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/kaniko
    
# 验证安装
RUN kaniko version
    
# 设置映射端口
EXPOSE 8086
EXPOSE 8888