
# 进入项目目录
cd D:\project\images\docker-file\jupyter-ai

# 构建镜像
docker build -t jupyter-ai:latest .


# 打标签并推送到仓库
docker tag jupyter-ai:latest r.mayishangshu.cn:82/dos/jupyter-ai:latest

docker push r.mayishangshu.cn:82/dos/jupyter-ai:latest