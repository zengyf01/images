#!/usr/bin/env bash
# 3.0/entrypoint.sh
# 容器启动入口:
#   1) 读环境变量注入 git 身份(无则用默认值)
#   2) 准备 /root/.ssh(支持运行时挂载密钥 / ssh-agent socket)
#   3) 打印启动信息
#   4) exec 启动 jupyter lab

set -e

# ---------- 1) git 用户身份 ----------
: "${GIT_USER_NAME:=Jupyter User}"
: "${GIT_USER_EMAIL:=jupyter@local}"
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
# 让用户在 jupyterlab-git UI 里看到的 author 与 commit author 一致
git config --global commit.gpgsign false 2>/dev/null || true

# ---------- 2) 准备 SSH ----------
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# 如果只挂了私钥没挂 known_hosts,允许首次 host key 提示(strictHostKeyChecking=accept-new)
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
    echo "[entrypoint] ssh-agent socket forwarded: $SSH_AUTH_SOCK"
fi
# 写一份 ssh config 模板,让用户后续挂 config 时可覆盖
cat > /root/.ssh/config <<'SSHCFG' 2>/dev/null || true
Host *
    StrictHostKeyChecking accept-new
    UserKnownHostsFile=/root/.ssh/known_hosts
SSHCFG
chmod 600 /root/.ssh/config 2>/dev/null || true

# ---------- 2.5) 拉取外部 git 仓库(由环境变量控制) ----------
# 镜像本身不预置任何 git 仓库,启动时根据 GIT_REPO_URL 拉取外部仓库。
# 地址由运维侧通过环境变量 / K8s ConfigMap 注入,使用者无需知道具体地址。
: "${GIT_REPO_URL:=}"          # 例如 https://github.com/xxx/yyy.git 或 git@github.com:xxx/yyy.git
: "${GIT_REPO_BRANCH:=main}"   # 默认 main
: "${GIT_REPO_DIR:=/root/work}"  # 仓库 clone 到哪里;默认 /root/work
: "${GIT_REPO_USER:=}"         # 可选;HTTP(S) 私有仓库的用户名
: "${GIT_REPO_TOKEN:=}"        # 可选;HTTP(S) 私有仓库的密码/token,会自动拼到 URL 里,clone 完成后从 .git/config 抹掉

if [ -n "$GIT_REPO_URL" ]; then
    # 推导仓库名(去掉协议和 .git 后缀,只留最后一段路径)
    REPO_NAME="$(basename "$GIT_REPO_URL" .git)"

    # 如果 GIT_REPO_DIR 是默认的 /root/work 且 URL 给了具体仓库,自动用仓库名建子目录
    if [ "$GIT_REPO_DIR" = "/root/work" ]; then
        TARGET_DIR="/root/work/$REPO_NAME"
    else
        TARGET_DIR="$GIT_REPO_DIR"
    fi

    if [ -d "$TARGET_DIR/.git" ]; then
        echo "[entrypoint] repo already cloned at $TARGET_DIR, fetching latest ..."
        cd "$TARGET_DIR"
        git fetch --all --prune || true
        git checkout "$GIT_REPO_BRANCH" 2>/dev/null || git checkout -b "$GIT_REPO_BRANCH"
        git pull --ff-only 2>/dev/null || true
    else
        # 处理 HTTP(S) + token(可选 + user):http(s)://... -> http(s)://USER:TOKEN@...
        # 重要:必须 URL-encode 凭证,否则密码里的 : / * @ 会破坏 URL 结构
        CLONE_URL="$GIT_REPO_URL"
        if [ -n "$GIT_REPO_TOKEN" ] && [[ "$CLONE_URL" == http*://* ]]; then
            # 去掉原 URL 里的 user@ 部分(若有,避免重复拼接)
            CLONE_URL="$(echo "$CLONE_URL" | sed -E 's#(https?)://[^@/]*@#\1://#')"
            # 用 python3 URL-encode 凭证(用户名和密码各自 encode)
            ENCODED_USER="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${GIT_REPO_USER:-}")"
            ENCODED_TOKEN="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$GIT_REPO_TOKEN")"
            # 拼接凭证:有用户名用 USER:TOKEN,没有用 oauth2:TOKEN(git 通用)
            if [ -n "$GIT_REPO_USER" ]; then
                CLONE_URL="$(echo "$CLONE_URL" | sed -E "s#(https?://)#\\1${ENCODED_USER}:${ENCODED_TOKEN}@#")"
            else
                CLONE_URL="$(echo "$CLONE_URL" | sed -E "s#(https?://)#\\1oauth2:${ENCODED_TOKEN}@#")"
            fi
            # clone 完后,要配 credential helper,让后续 push 自动用凭证
            USE_TOKEN=1
        fi
        echo "[entrypoint] cloning (branch=$GIT_REPO_BRANCH) -> $TARGET_DIR"
        echo "[entrypoint]   source: $GIT_REPO_URL"
        mkdir -p "$(dirname "$TARGET_DIR")"
        # 临时关闭 errexit,失败时让下面的诊断段有机会输出
        set +e
        git clone --branch "$GIT_REPO_BRANCH" --single-branch "$CLONE_URL" "$TARGET_DIR"
        CLONE_RC=$?
        set -e
        if [ "${USE_TOKEN:-0}" = "1" ]; then
            cd "$TARGET_DIR"
            # 1) 配 git credential helper,让 git 自动用 ~/.git-credentials 里的凭证
            git config --global credential.helper store
            # 2) 把凭证写到 ~/.git-credentials(明文,但 git 标准位置,权限 600)
            PROTOCOL="http"
            [[ "$GIT_REPO_URL" == https://* ]] && PROTOCOL="https"
            HOST_PATH="$(echo "$GIT_REPO_URL" | sed -E 's#https?://##')"
            echo "${PROTOCOL}://${ENCODED_USER}:${ENCODED_TOKEN}@${HOST_PATH}" > ~/.git-credentials
            chmod 600 ~/.git-credentials
            # 3) 把 .git/config 的 origin URL 改回无凭证形式(可选,但更干净)
            git remote set-url origin "$GIT_REPO_URL"
            echo "[entrypoint] credential helper 已配: ~/.git-credentials"
        fi
        if [ $CLONE_RC -ne 0 ]; then
            echo "[entrypoint] =============================================="
            echo "[entrypoint] ERROR: git clone failed (rc=$CLONE_RC)"
            echo "[entrypoint]   source URL : $GIT_REPO_URL"
            echo "[entrypoint]   target dir : $TARGET_DIR"
            echo "[entrypoint]   branch     : $GIT_REPO_BRANCH"
            echo "[entrypoint]   user       : ${GIT_REPO_USER:-<empty>}"
            echo "[entrypoint]   token len  : ${#GIT_REPO_TOKEN} chars"
            echo "[entrypoint] =============================================="
            echo "[entrypoint] 排查:"
            echo "[entrypoint]   1) 网络: docker exec <container> curl -v $GIT_REPO_URL"
            echo "[entrypoint]   2) 凭证: GIT_REPO_USER / GIT_REPO_TOKEN 是否正确(密码含特殊字符要单引号)"
            echo "[entrypoint]   3) 分支: GIT_REPO_BRANCH=$GIT_REPO_BRANCH 是否存在"
            echo "[entrypoint]   4) 协议: 是 http(s) 还是 ssh?ssh 需要挂 SSH key,不是 token"
            exit $CLONE_RC
        fi
    fi

    # 切到仓库目录,作为 JupyterLab 工作目录
    cd "$TARGET_DIR"
    # 给这个仓库单独设 user(避免覆盖全局)
    git config user.name  "$GIT_USER_NAME"
    git config user.email "$GIT_USER_EMAIL"
    echo "[entrypoint] cwd: $(pwd)"
fi

# ---------- 3) 启动信息 ----------
echo "=================================================================="
echo " kaniko-jupyterlab:3.0"
echo " - jupyterlab: $(jupyter lab --version 2>&1 | head -1 || echo unknown)"
echo " - git:        $(git --version)"
echo " - git user:   $(git config --global user.name) <$(git config --global user.email)>"
echo " - kaniko:     $(kaniko version 2>&1 | head -1 || echo unknown)"
echo " - workdir:    $(pwd)"
[ -n "$GIT_REPO_URL" ] && echo " - repo:       $GIT_REPO_URL (branch=$GIT_REPO_BRANCH)"
echo " - jupyterlab-git extension:"
jupyter server extension list 2>&1 | grep -E "jupyterlab_git" || echo "   (not enabled)"
echo "=================================================================="

# ---------- 4) 启动 jupyter ----------
exec jupyter lab \
    --config=/root/.jupyter/jupyter_lab_config.py \
    --allow-root \
    --no-browser
