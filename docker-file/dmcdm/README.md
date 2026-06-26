
# 进入项目目录
cd D:\project\images\docker-file\dmcdm

# 构建镜像
docker build -t dmcdm:latest .


# 打标签并推送到仓库
docker tag dmcdm:latest r.mayishangshu.cn:82/dev/dmcdm:latest

docker push r.mayishangshu.cn:82/dev/dmcdm:latest


# 备注
dmcdm版本：v1.1
如果windows下构建报错，请到ubuntu下构建