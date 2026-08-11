
# 该版本基于1.0，修复了跨域和远程访问支持

# 进入项目目录
cd D:\project\images\docker-file\jupyter-secretflow

# 构建镜像
docker build --no-cache -t kaniko-jupyterlab-secretflow:1.0 .


# 打标签并推送到仓库
docker tag kaniko-jupyterlab-secretflow:1.0 r.mayishangshu.cn:82/dos/kaniko-jupyterlab-secretflow:1.0

docker push r.mayishangshu.cn:82/dos/kaniko-jupyterlab-secretflow:1.0


# k8s中如果未读到最新的则删除下载的镜像
crictl images
crictl rmi r.mayishangshu.cn:82/dos/kaniko-jupyterlab-secretflow:1.0