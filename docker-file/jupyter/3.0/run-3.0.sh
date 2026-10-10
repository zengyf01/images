#!/usr/bin/env bash
# 3.0/run-3.0.sh
# 一键构建并启动 kaniko-jupyterlab:3.0,自动从你内网仓库 clone
# 用法:在 Git Bash 里跑 bash 3.0/run-3.0.sh

set -e

cd "$(dirname "$0")/.."

echo "=================================================================="
echo " 步骤 1/4:构建镜像(可能 3~10 分钟,首次)"
echo "=================================================================="
docker build --no-cache -t kaniko-jupyterlab:3.0 ./3.0

echo
echo "=================================================================="
echo " 步骤 2/4:清理旧容器(如有)"
echo "=================================================================="
docker rm -f jupyter-git 2>/dev/null && echo "已删除旧容器" || echo "没有旧容器"

echo
echo "=================================================================="
echo " 步骤 3/4:启动新容器"
echo "=================================================================="
docker run -d \
  --name jupyter-git \
  -p 8888:8888 \
  -p 8086:8086 \
  -e 'GIT_REPO_URL=http://192.168.1.2/ssw/nax.git' \
  -e 'GIT_REPO_USER=zyf' \
  -e 'GIT_REPO_TOKEN=ON:L/3d*' \
  -e 'GIT_REPO_BRANCH=main' \
  -e 'GIT_USER_NAME=zyf' \
  -e 'GIT_USER_EMAIL=ON:L/3d*' \
  kaniko-jupyterlab:3.0

echo
echo "=================================================================="
echo " 步骤 4/4:跟踪启动日志(实时,看到 'cwd: /root/work/nax' 就成功了)"
echo "             Ctrl+C 退出,容器继续在后台跑"
echo "=================================================================="
echo "3 秒后开始跟踪日志 ..."
sleep 3
docker logs -f jupyter-git
