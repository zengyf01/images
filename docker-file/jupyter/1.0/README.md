
# 提交了kaniko

# 进入项目目录
cd D:\project\images\docker-file\jupyter

# 构建镜像
docker build -t kaniko-jupyterlab:1.0 ./1.0


# 打标签并推送到仓库
docker tag kaniko-jupyterlab:1.0 r.mayishangshu.cn:82/dos/kaniko-jupyterlab:1.0

docker push r.mayishangshu.cn:82/dos/kaniko-jupyterlab:1.0