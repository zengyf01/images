
# kaniko-jupyterlab:3.0

> 3.0 基于 2.0,新增 **JupyterLab 页面内嵌 Git UI**(`jupyterlab-git 0.44.0`),
> 并支持**通过环境变量拉取外部 git 仓库**。
>
> **3.0 的设计**:镜像**本身不预置任何仓库**,启动时由 `GIT_REPO_URL` 环境变量拉取外部仓库。
> 该地址由运维侧在 K8s ConfigMap / docker-compose 中配好,**使用者启动时不需要知道 git 地址**。
>
> ⚠️ **版本踩坑经验**:`jupyterlab-git 0.50.x` 系列需要 JupyterLab 4.x,跟 3.6.x **不兼容**。
> 0.41.0 还有一个 bug —— 左侧栏 Git 图标会缺失。**务必用 0.44.0**(本镜像钉死)。

---

## 与 2.0 的差异

| 项 | 2.0 | 3.0 |
|---|---|---|
| JupyterLab 版本 | 基础镜像默认(可能 1.x) | 升级到 **3.6.8** |
| Node.js | ❌ 未装(jupyter lab build 需要) | ✅ **20.16.0**(从 nodejs.org 预编译二进制) |
| 前端 assets | ❌ 未编译(Git 面板按钮不显示) | ✅ **已 `jupyter lab build`** |
| Git CLI | ❌ 未装 | ✅ 2.34.1 |
| JupyterLab Git UI | ❌ 无 | ✅ 左侧栏 Git 图标 + Git 面板(**jupyterlab-git==0.44.0**) |
| Git 仓库来源 | 用户手动 clone | 启动时**自动从外部仓库拉取**(环境变量传入地址) |
| 私有仓库支持 | ❌ 不支持 | ✅ HTTP(S) token / 凭证写在 URL / SSH 挂密钥 / ssh-agent socket |
| git 用户身份 | 容器内默认 | 通过 `GIT_USER_NAME` / `GIT_USER_EMAIL` 环境变量注入 |
| kaniko / 科学栈 / 跨域配置 | 保留 | 保留 |

---

## 一、环境变量清单

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `GIT_REPO_URL` | ✅ 是 | 空 | 外部仓库地址,见下方"凭证传递的 2 种方式" |
| `GIT_REPO_BRANCH` | 否 | `main` | 要 clone 的分支 |
| `GIT_REPO_DIR` | 否 | `/root/work/<repo-name>` | clone 到哪个目录 |
| `GIT_REPO_USER` | 否 | 空 | HTTP(S) 私有仓库的用户名(配合 `GIT_REPO_TOKEN` 用) |
| `GIT_REPO_TOKEN` | 否 | 空 | HTTP(S) 私有仓库的密码/token,自动 URL-encode,clone 完成后从 `.git/config` 抹掉 |
| `GIT_USER_NAME` | 否 | `Jupyter User` | **commit 时的 author 姓名**(不是 git 凭证) |
| `GIT_USER_EMAIL` | 否 | `jupyter@local` | **commit 时的 author 邮箱**(不是 git 凭证) |

> **关键**:`GIT_REPO_URL` 等仓库相关变量建议放在 **K8s ConfigMap / docker-compose .env** 里统一管理,**不要**让每个使用者自己填。
> `GIT_USER_NAME` / `GIT_USER_EMAIL` 是**代码提交署名**,跟仓库凭证无关,通常填个人/团队真名 + 真实 email。

---

## 二、凭证传递的 5 种方式

### ⚠️ 重要概念:**clone 凭证和 push 凭证是两件事**

entrypoint.sh 只在**容器启动时**用 `GIT_REPO_USER`/`GIT_REPO_TOKEN` 拉一次代码。
**之后你在 UI 里 commit + push**,push 用的是 `.git/config` 里的 remote URL(可能是含凭证的、可能是干净的)。
- 方式 A 启动 → .git/config **有**凭证 → push 自动带凭证成功
- 方式 B 启动 → entrypoint 会在 clone 完后**抹掉** .git/config 里的凭证 → push 失败(需要重启容器再传 token,或配 credential helper)
- 方式 C/D 启动 → .git/config **没**凭证(SSH 走 ~/.ssh) → push 走 SSH key 成功

### 方式 A:把凭证写在 `GIT_REPO_URL` 里(最简单,推荐)

URL 里直接含 `用户名:密码@host`,**特殊字符必须 URL-encode**:
- `:` → `%3A`、`/` → `%2F`、`*` → `%2A`、`@` → `%40`

```bash
docker run -d --name jupyter-git \
  -p 8888:8888 -p 8086:8086 \
  -e 'GIT_REPO_URL=http://zyf:ON%3AL%2F3d*@192.168.1.2:8080/ssw/nax.git' \
  -e 'GIT_REPO_BRANCH=main' \
  -e 'GIT_USER_NAME=zyf' \
  -e 'GIT_USER_EMAIL=zyf@your-company.com' \
  kaniko-jupyterlab:3.0
```

**特点**:
- 整个 `-e` 值用**单引号**包(bash 不会展开 `*` / `:`)
- 你的密码 `ON:L/3d*` 必须先手动 encode 成 `ON%3AL%2F3d%2A`(推荐,`*` 也要 encode)
- `git clone` 成功后,这个 URL **完整(含凭证)**留在 `.git/config` 里
- ✅ 后续 `git push` **会带**这个 URL 里的凭证,直接成功
- ⚠️ 凭证会以明文形式写在容器内 `/root/work/<repo>/.git/config`(其他能进容器的人能看到)
- ⚠️ 容器重启后要重新传一遍 URL(entrypoint 不会自动抹掉)

### 方式 B:用 `GIT_REPO_USER` + `GIT_REPO_TOKEN`(直接传密码,push 免输)

**这是"直接指定密码"的推荐方式**。启动时传用户名 + 密码,entrypoint 自动:
1. URL-encode 后拼到 URL 拉仓库
2. 配 `git credential.helper = store`
3. 写凭证到 `~/.git-credentials`(chmod 600)
4. `.git/config` 的 origin URL 改回**无凭证**形式
5. 后续 `git push` **自动**从 credential helper 拿凭证,**不用再输密码**

```bash
docker run -d --name jupyter-git \
  -p 8888:8888 -p 8086:8086 \
  -e 'GIT_REPO_URL=http://192.168.1.2:8080/ssw/nax.git' \
  -e 'GIT_REPO_USER=zyf' \
  -e 'GIT_REPO_TOKEN=ON:L/3d*' \
  -e 'GIT_REPO_BRANCH=main' \
  -e 'GIT_USER_NAME=zyf' \
  -e 'GIT_USER_EMAIL=zyf@your-company.com' \
  kaniko-jupyterlab:3.0
```

**注意**:
- `-e` 值仍用**单引号**(bash 不会展开 `*`)
- 密码里的 `:` `/` `*` **不用**手动 URL-encode,entrypoint 内部自动
- 启动后容器内有 2 个地方可能含凭证:
  - `~/.git-credentials`(chmod 600,标准位置)
  - 没了(`.git/config` 是干净的)
- ✅ 后续 `git push` **直接成功**,不用任何额外操作
- ⚠️ main 分支**仍**受保护(要切到 feature 分支)

### 方式 C:SSH 私有仓库(挂密钥)

```bash
docker run -d --name jupyter-git \
  -p 8888:8888 -p 8086:8086 \
  -e 'GIT_REPO_URL=git@github.com:your-org/private-repo.git' \
  -e 'GIT_REPO_BRANCH=main' \
  -e 'GIT_USER_NAME=zyf' \
  -e 'GIT_USER_EMAIL=zyf@your-company.com' \
  -v ~/.ssh/id_ed25519:/root/.ssh/id_ed25519:ro \
  -v ~/.ssh/known_hosts:/root/.ssh/known_hosts:ro \
  kaniko-jupyterlab:3.0
```

**特点**:
- SSH URL 不走 entrypoint 的 HTTP 处理逻辑(只对 `http://` `https://` 生效)
- 容器内 `~/.ssh/` 预置 chmod 700,可挂密钥/ssh-agent
- ✅ 后续 `git push` 直接用 SSH key,不需要额外配

### 方式 D:转发 ssh-agent socket(多密钥场景)

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519

docker run -d --name jupyter-git \
  -p 8888:8888 -p 8086:8086 \
  -e 'GIT_REPO_URL=git@github.com:your-org/private-repo.git' \
  -e 'GIT_REPO_BRANCH=main' \
  -e 'GIT_USER_NAME=zyf' \
  -e 'GIT_USER_EMAIL=zyf@your-company.com' \
  -v $SSH_AUTH_SOCK:/ssh-agent \
  -e SSH_AUTH_SOCK=/ssh-agent \
  kaniko-jupyterlab:3.0
```

**特点**:
- 主机 ssh-agent socket 转发进容器,容器用主机的所有已加载密钥
- 密钥不落盘、不进镜像,安全等级最高

### 方式 E:不传 `GIT_REPO_URL`(空目录启动)

`GIT_REPO_URL` 不传,容器**跳过 clone**,直接启动 JupyterLab,工作目录 `/root/work`(空)。
用户可在 UI 里手动点 Git 面板的 "Clone a Repository" 输入仓库地址。

---

### 📊 5 种方式对比

| 方式 | clone 凭证 | push 凭证 | 容器内有凭证明文 | 推荐度 |
|---|---|---|---|---|
| **A** 写 URL | URL 里 | URL 里(自动) | ⚠️ 是(.git/config) | ⭐⭐⭐⭐ 简单场景 |
| **B** USER+TOKEN | 自动拼(URL-encode) | **自动用 helper**(免输密码) | ⚠️ 是(~/.git-credentials) | ⭐⭐⭐⭐⭐ **直接传密码** |
| **C** SSH 密钥 | SSH key | SSH key(自动) | ⚠️ 密钥(挂载的) | ⭐⭐⭐⭐⭐ 私有仓库 |
| **D** ssh-agent | 主机 agent | 主机 agent | ✅ 否(只 socket) | ⭐⭐⭐⭐⭐ 多密钥 |
| **E** 不传 | 手动 | 手动 | — | ⭐⭐ 测试用 |

**3.0 推荐**:
- **直接传密码**:用方式 B(启动时传 `GIT_REPO_USER` + `GIT_REPO_TOKEN`,push 免输)
- 公开仓库:用方式 A(简单)
- 私有仓库 + 单密钥:用方式 C
- 私有仓库 + 多密钥:用方式 D
- 内部信任网络 + 最简:用方式 A

---

## 三、构建与推送

### 方法 1:用一键脚本(推荐)

```bash
cd D:\project\images\docker-file\jupyter
bash 3.0/run-3.0.sh
```
脚本自动:`docker build` → 删旧容器 → 启动新容器 → 实时跟日志。Ctrl+C 退出日志跟踪,容器继续跑。

### 方法 2:手动(沿用 1.0 / 2.0 风格)

```bash
cd D:\project\images\docker-file\jupyter

# 构建(首次 5-10 分钟,增量 30 秒)
docker build -t kaniko-jupyterlab:3.0 ./3.0

# 打标签并推送
docker tag kaniko-jupyterlab:3.0 r.mayishangshu.cn:82/dos/kaniko-jupyterlab:3.0
docker push r.mayishangshu.cn:82/dos/kaniko-jupyterlab:3.0

# k8s 中如果未读到最新的则删除下载的镜像
crictl images
crictl rmi r.mayishangshu.cn:82/dos/kaniko-jupyterlab:3.0
```

---

## 四、页面 Git UI 使用流程(已自动 clone 场景)

### 1. 打开 Git 面板

浏览器开 `http://<host>:8888` + **Ctrl+Shift+R 强刷**(清 labextension 缓存)。**左侧栏从上到下第 3 个图标**(分支形,`data-id="jp-git-sessions"`)点开 → 右侧出现 Git 面板。

### 2. 完整 commit + push 流程

```
① 左侧栏点 [Git 图标] → 面板打开,显示 Current Branch + Changed
② 左侧栏点 [File Browser 图标] → 双击 README.md → 中间编辑器打开
③ 末尾加字 → Ctrl+S 保存
④ 回到 [Git 图标] → Changed 列表里勾选 README.md(显示 M 标记)
⑤ Summary 输入框填 message(例:test: 改 README)
⑥ 点底部 [COMMIT 按钮] → Past Commits 多一条
⑦ 切到 feature 分支(避免 main 受保护):顶部 [main ▼] 下拉 → 输 feature/xxx → 回车
⑧ 顶部 [Git 菜单] → [Push to Remote] ← 推荐
   或者打开 Terminal 跑 git push ← 也行
⑨ 到 GitLab 看新分支有内容 + 发 Merge Request
```

### 3. 两种 push 方式

| 方式 | 操作 | 适用 |
|---|---|---|
| **Git 菜单** | 顶部 **Git 菜单** → **Push to Remote** | 日常单次推送,UI 直观 |
| **Terminal** | 打开 Terminal → `git push` | 批量、复杂操作、调试 |

---

## 五、GitLab 上 main 分支受保护的重要约束

**默认行为**:`main` 分支是 GitLab 受保护分支,zyf 这种 Developer 角色**无法直接 push 到 main**。

```
remote: GitLab: You are not allowed to push code to protected branches on this project.
```

**正确流程**:
1. 改动 → 切到新分支 `feature/your-name` → commit
2. push 到 `feature/your-name`
3. GitLab 上发 **Merge Request**:`feature/your-name` → `main`
4. 管理员 review 后合并

**绕过 main 保护**(任选其一):
- 联系项目 owner,把你升为 `Maintainer`
- GitLab 项目 → Settings → Repository → Protected branches → 允许 Developers push

---

## 六、关键组件版本(构建后验证)

```bash
docker run --rm kaniko-jupyterlab:3.0 jupyter lab --version
# 预期:3.6.8

docker run --rm kaniko-jupyterlab:3.0 jupyter server extension list | grep jupyterlab_git
# 预期:jupyterlab_git 0.44.0 OK

docker run --rm kaniko-jupyterlab:3.0 jupyter labextension list | grep '@jupyterlab/git'
# 预期:@jupyterlab/git v0.44.0 enabled OK(无 X 标记)

docker run --rm kaniko-jupyterlab:3.0 git --version
# 预期:git version 2.34.1

docker run --rm kaniko-jupyterlab:3.0 node --version
# 预期:v20.16.0

docker run --rm kaniko-jupyterlab:3.0 kaniko version | head -1
# 预期:Kaniko version : v1.23.2
```

**镜像大小**:约 **3.5GB**(含 node 20 + jupyterlab-git 编译产物)

---

## 七、构建前的前置实测(可选)

```bash
bash 3.0/precheck.sh
```

确认基础镜像里 jupyterlab / git / Python / OS 真实版本(决定 Dockerfile 兼容性)。

---

## 八、回滚

3.0 不可用时,可回退到 `kaniko-jupyterlab:2.0`,Dockerfile / 启动方式均向下兼容。

---

## 九、踩坑经验(避免重复掉坑)

| 坑 | 原因 | 解决 |
|---|---|---|
| Git 面板只有 Help,没按钮 | `pip install` 没编译前端 assets | 装 Node 20 + 跑 `jupyter lab build` |
| `lib0@0.2.63` 报 `engine incompatible` | apt 默认 nodejs 12 太老 | 装 node 20 预编译二进制(用 nodejs.org) |
| `jupyterlab-git 0.50.x` build 失败 | 0.50.x 需要 jupyterlab 4.x | 用 0.44.0(最后兼容 jupyterlab 3.x 的版本) |
| `0.41.0` 左侧栏 Git 图标缺失 | 已知 bug,extensions 注册不完整 | 用 0.44.0 |
| `git clone` 报 `not valid: is this a git repository?` | URL 是 80 端口的 nginx 壳子 | 用真实服务端口(如 8080) |
| URL 里的 `:` 被 bash 当端口分隔 | bash 命令行解析 | 整个 URL 用**单引号**包起来 |
| URL 里的密码含 `:` `/` `*` | URL 分隔符冲突 | URL-encode: `%3A` `%2F` `%2A` |
| 凭证留在 `.git/config` 被人看到 | 用方式 A 写在 URL 里 | 改用方式 B(GIT_REPO_USER + GIT_REPO_TOKEN) |
| 浏览器缓存导致 Git 面板只显示旧版 | 旧 labextension 缓存 | **Ctrl+Shift+R 强刷** |
| push 到 main 被拒绝 | GitLab 分支保护 | 切到 feature 分支 + 发 MR |
