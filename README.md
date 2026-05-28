
## 基础镜像secretflow 1.14.0b0

    FROM r.mayishangshu.cn:82/public/jupyterlab:1.0
    # RUN pip3 install -U secretflow uvicorn ray gradio  -i https://pypi.org/simple/
    
    RUN pip3 install \
        secretflow==1.14.0b0 \
        ray[default]==2.9.3 \
        uvicorn==0.27.0 \
        gradio==3.50.2 \
        -i https://pypi.org/simple/
    
    # 设置映射端口
    EXPOSE 8086
    EXPOSE 8088



## secretflow 1.13.0b0 基础镜像

    FROM r.mayishangshu.cn:82/public/jupyterlab:1.0
    # RUN pip3 install -U secretflow uvicorn ray gradio  -i https://pypi.org/simple/
    
    RUN pip3 install \
        secretflow==1.13.0b0 \
        ray[default]==2.42.0 \
        uvicorn==0.27.0 \
        gradio==3.50.2 \
        -i https://pypi.org/simple/
    
    # 设置映射端口
    EXPOSE 8086
    EXPOSE 8088


## jupyterlab-secretflow 1.10.0b0 基础镜像 （该版本支持pir,推荐）

    FROM r.mayishangshu.cn:82/public/jupyterlab:1.0
    # RUN pip3 install -U secretflow uvicorn ray gradio  -i https://pypi.org/simple/
    

    RUN pip3 install \
        secretflow==1.10.0b0 \
        ray[default] \
        uvicorn \
        gradio \
        -i https://pypi.org/simple/ \
        --no-cache-dir
    
    # 设置映射端口
    EXPOSE 8086
    EXPOSE 8088


## kaniko-jupyterlab-secretflow 1.10.0b0 基础镜像 （该版本支持pir,支持kaniko（jupyter中构建镜像），推荐）

    # 基础镜像
    FROM r.mayishangshu.cn:82/public/jupyterlab:1.0
    
    # 安装 Python 依赖
    RUN pip3 install \
        secretflow==1.10.0b0 \
        ray[default] \
        uvicorn \
        gradio \
        -i https://pypi.org/simple/ \
        --no-cache-dir
    
    # 从 kaniko 官方镜像复制 kaniko 可执行文件
    COPY --from=gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/kaniko
    
    # 验证安装
    RUN kaniko version
    
    # 设置映射端口
    EXPOSE 8086
    EXPOSE 8088



## kaniko-jupyterlab1.10.0b0 基础镜像 （支持kaniko（jupyter中构建镜像），推荐）
    
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
    EXPOSE 8088



##  sandbox-python:3.7-slim
    FROM python:3.7-slim
    
    # 设置工作目录
    WORKDIR /app
    
    # 将当前目录的内容复制到容器的/app目录
    COPY . /app
    
    # 安装 Python 依赖
    RUN pip install --no-cache-dir requests


## sandbox-python:3.7-slim 镜像构建
    docker build -t sandbox-python:3.7-slim .




## sandbox-secretflow:1.10.0b0 

FROM python:3.7-slim

# 安装依赖
RUN pip3 install --no-cache-dir \
    secretflow==1.10.0b0 \
    ray[default] \
    uvicorn \
    gradio \
    -i https://pypi.org/simple/




## sandbox-secretflow:1.10.0b0 

    docker build -t sandbox-secretflow:1.10.0b0 .






## 开发环境启动

docker run -d -p 5555:5555 -p 8265:8265 -p 7860:7860 `
  -v "D:\project\privacy-computing\alice:/work" `
  --name alice-secretflow-jupyter `
  r.mayishangshu.cn:82/dos/jupyterlab-secretflow:1.10.0b0 `
  jupyter lab --port=5555 --ip=0.0.0.0 --allow-root


docker run -d -p 7777:7777  `
  -v "D:\project\privacy-computing\bob:/work" `
  --name bob-secretflow-jupyter `
  r.mayishangshu.cn:82/dos/jupyterlab-secretflow:1.10.0b0 `
  jupyter lab --port=7777 --ip=0.0.0.0 --allow-root



