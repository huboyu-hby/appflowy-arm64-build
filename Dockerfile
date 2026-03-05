 统一设置构建参数，减少重复代码
ARG BASE_IMAGE=ubuntu:22.04
ARG TARGETARCH  # Docker buildx自动注入的架构变量(x86_64/arm64)

#================
# 通用构建阶段 - 提取重复逻辑
#================
FROM ${BASE_IMAGE} as builder-common

# 基础配置：国内镜像源 + 错误终止 + 时区
ENV DEBIAN_FRONTEND=noninteractive
RUN set -e && \
    # 替换国内阿里云源
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    cmake \
    ninja-build \
    pkg-config \
    libssl-dev \
    libgl1-mesa-dev \
    libx11-xcb-dev \
    libxcb-icccm4-dev \
    libxcb-image0-dev \
    libxcb-keysyms1-dev \
    libxcb-randr0-dev \
    libxcb-render-util0-dev \
    libxcb-xinerama0-dev \
    libxcb-xfixes0-dev \
    libxcb-cursor-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libicu-dev \
    libinput-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libxi-dev \
    libxrandr-dev \
    libxrender-dev \
    libxtst-dev \
    libkeybinder-3-0-dev \
    libnotify-dev \
    libsqlite3-dev \
    libjemalloc-dev \
    libzstd-dev \
    librocksdb-dev \
    clang \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 创建appflowy用户并配置免密sudo
ARG user=appflowy
RUN useradd --system --create-home $user && \
    echo "$user ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

# 提前设置Flutter国内镜像（关键：安装前配置，确保加速生效）
ENV PUB_HOSTED_URL=https://pub.flutter-io.cn
ENV FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 切换到appflowy用户，设置工作目录
USER $user
WORKDIR /home/$user

# 安装Rust（确保环境变量全局生效）
RUN set -e && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    # 将cargo环境变量写入bashrc，确保后续shell生效
    echo "source ~/.cargo/env" >> ~/.bashrc && \
    # 激活环境并安装指定版本的Rust
    . ~/.cargo/env && \
    rustup toolchain install 1.81 && \
    rustup default 1.81

# 安装Flutter（国内镜像）
RUN set -e && \
    curl -sSfL \
    --output flutter.tar.xz \
    https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.4-stable.tar.xz && \
    tar -xf flutter.tar.xz && \
    rm flutter.tar.xz && \
    # 配置Flutter路径并启用Linux桌面支持
    echo "export PATH=\$PATH:/home/$user/flutter/bin:/home/$user/flutter/bin/cache/dart-sdk/bin:/home/$user/.pub-cache/bin" >> ~/.bashrc && \
    . ~/.bashrc && \
    flutter config --enable-linux-desktop && \
    flutter doctor && \
    dart pub global activate protoc_plugin 21.1.2

# 安装cargo相关工具（构建缓存优化：依赖安装与代码解耦）
RUN set -e && \
    . ~/.cargo/env && \
    cargo install cargo-make --version 0.37.18 --locked && \
    cargo install cargo-binstall --version 1.10.17 --locked && \
    cargo binstall duckscript_cli --locked -y

#================
# 架构专属构建阶段
#================
FROM builder-common as builder-x86_64
# 架构专属配置
ARG ROCKSDB_LIB_DIR="/usr/lib/x86_64-linux-gnu/"
ARG BUILD_PROFILE="production-linux-x86_64"
ARG BUILD_PATH="linux/x64/release/bundle"

# 复制代码（最后复制，利用Docker缓存）
COPY . /appflowy
RUN sudo chown -R $USER: /appflowy
WORKDIR /appflowy/frontend

# 构建AppFlowy
RUN set -e && \
    . ~/.bashrc && \
    cargo make appflowy-flutter-deps-tools && \
    cargo make flutter_clean && \
    OPENSSL_STATIC=1 ZSTD_SYS_USE_PKG_CONFIG=1 ROCKSDB_LIB_DIR=${ROCKSDB_LIB_DIR} \
    cargo make -p ${BUILD_PROFILE} appflowy-linux

FROM builder-common as builder-arm64
# 架构专属配置
ARG ROCKSDB_LIB_DIR="/usr/lib/aarch64-linux-gnu/"
ARG BUILD_PROFILE="production-linux-aarch64"
ARG BUILD_PATH="linux/arm64/release/bundle"

# 复制代码
COPY . /appflowy
RUN sudo chown -R $USER: /appflowy
WORKDIR /appflowy/frontend

# 构建AppFlowy（arm64额外参数）
RUN set -e && \
    . ~/.bashrc && \
    cargo make appflowy-flutter-deps-tools && \
    cargo make flutter_clean && \
    OPENSSL_STATIC=1 ZSTD_SYS_USE_PKG_CONFIG=1 ROCKSDB_LIB_DIR=${ROCKSDB_LIB_DIR} \
    FLUTTER_DESKTOP_FEATURES="dart,openssl_vendored" \
    cargo make -p ${BUILD_PROFILE} appflowy-linux

#================
# 通用运行阶段
#================
FROM ${BASE_IMAGE} as app-common
# 安装运行时依赖
ENV DEBIAN_FRONTEND=noninteractive
RUN set -e && \
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libx11-xcb1 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xfixes0 \
    libxcb-cursor0 \
    libfontconfig1 \
    libfreetype6 \
    libharfbuzz0b \
    libicu70 \
    libinput10 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxtst6 \
    libkeybinder-3-0 \
    libnotify4 \
    libsqlite3-0 \
    libjemalloc2 \
    libzstd1 \
    librocksdb6.15 \
    && rm -rf /var/lib/apt/lists/*

# 创建非root用户
ARG user=appflowy
ARG uid=1000
ARG gid=1000
RUN groupadd --gid $gid $user && \
    useradd --create-home --uid $uid --gid $gid $user
USER $user
WORKDIR /home/$user

#================
# 架构专属运行镜像
#================
FROM app-common as app-x86_64
# 复制x86_64编译产物
COPY --from=builder-x86_64 /appflowy/frontend/appflowy_flutter/build/linux/x64/release/bundle .
CMD ["./AppFlowy"]

FROM app-common as app-arm64
# 复制arm64编译产物
COPY --from=builder-arm64 /appflowy/frontend/appflowy_flutter/build/linux/arm64/release/bundle .
CMD ["./AppFlowy"]
