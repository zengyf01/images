#!/usr/bin/env bash
# 3.0/precheck.sh
# 实测基础镜像 r.mayishangshu.cn:82/public/jupyterlab:1.0 的环境,决定 Dockerfile 走 A1 还是 A2。
# 用法:在 Git Bash 或 Linux/Mac 终端执行 bash precheck.sh
# 需要本地能访问 r.mayishangshu.cn:82 的 Docker Registry,以及 docker 命令可用。

set -u

IMAGE="r.mayishangshu.cn:82/public/jupyterlab:1.0"

echo "=================================================================="
echo " 3.0 基础镜像实测: $IMAGE"
echo "=================================================================="
echo

echo ">> [1/5] 拉取基础镜像 ..."
docker pull "$IMAGE" 2>&1 | tail -5
echo

echo ">> [2/5] 启动一次性容器,探测环境 ..."
docker run --rm "$IMAGE" bash -c '
echo "--- OS ---"
cat /etc/os-release 2>/dev/null || cat /etc/issue
echo
echo "--- Python ---"
python3 --version 2>&1
which python3
echo
echo "--- JupyterLab ---"
jupyter lab --version 2>&1 || echo "jupyter lab 命令缺失"
jupyter notebook --version 2>&1 || echo "jupyter notebook 命令缺失"
echo
echo "--- Git ---"
git --version 2>&1 || echo "git 命令缺失"
which git
echo
echo "--- Node.js(jupyterlab-git 已编译扩展通常不需要) ---"
node --version 2>&1 || echo "node 命令缺失"
which node
echo
echo "--- 包管理器 ---"
which apt-get && echo "apt-get: OK" || echo "apt-get: MISSING"
which pip3 && echo "pip3: OK" || echo "pip3: MISSING"
echo
echo "--- 已装的 jupyter 扩展(server) ---"
jupyter server extension list 2>&1 || true
echo
echo "--- 已装的 jupyter 扩展(lab) ---"
jupyter labextension list 2>&1 || true
echo
echo "--- 当前用户 ---"
id
' 2>&1
echo

echo ">> [3/5] 镜像大小与层数 ..."
docker images "$IMAGE" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
echo

echo ">> [4/5] 镜像历史(后 15 层,看基础镜像里有什么) ..."
docker history "$IMAGE" --no-trunc 2>&1 | tail -15
echo

echo ">> [5/5] 判断建议(根据上面输出人工对照) ---"
cat <<'EOF'
==================================================================
 子路径判定表:
   A1(白嫖)  jupyter lab --version >= 3.5  且  git --version OK
   A2(升级)  上述任一不满足
==================================================================
  - 如果是 A1:Dockerfile 可省略 apt-get install git 和 jupyterlab 升级步骤
  - 如果是 A2:Dockerfile 必须 apt-get install -y git + 升级 jupyterlab
           并把 jupyterlab-git 钉到 0.50.2(兼容 jupyterlab 3.x)
EOF
