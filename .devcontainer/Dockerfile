FROM mcr.microsoft.com/vscode/devcontainers/base:0-bionic

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

ARG INSTALL_ZSH="false"
ARG UPGRADE_PACKAGES="true"
ARG ENABLE_NONROOT_DOCKER="true"
ARG USE_MOBY="true"
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
COPY library-scripts/*.sh /tmp/library-scripts/
RUN apt-get update \
    && /bin/bash /tmp/library-scripts/common-debian.sh "${INSTALL_ZSH}" "${USERNAME}" "${USER_UID}" "${USER_GID}" "${UPGRADE_PACKAGES}" "true" "true" \
    # Use Docker script from script library to set things up
    && /bin/bash /tmp/library-scripts/docker-debian.sh "${ENABLE_NONROOT_DOCKER}" "/var/run/docker-host.sock" "/var/run/docker.sock" "${USERNAME}" \
    # Clean up
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts/

# https://github.com/docker-library/mysql/blob/master/5.7/Dockerfile.debian
# apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys A4A9406876FCBD3C456770C88C718D3B5072E1F5 || \
# apt-key adv --keyserver pgp.mit.edu --recv-keys A4A9406876FCBD3C456770C88C718D3B5072E1F5 || \
# apt-key adv --keyserver keyserver.pgp.com --recv-keys A4A9406876FCBD3C456770C88C718D3B5072E1F5
COPY mysql-public-key /tmp/mysql-public-key
RUN apt-key add /tmp/mysql-public-key

# Configure apt and install packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-utils dialog 2>&1 \
    && apt-get install -y \
        iproute2 \
        procps \
        sudo \
        bash-completion \
        build-essential \
        curl \
        wget \
        software-properties-common \
        direnv \
        tzdata \
        python3-pip \
    && echo 'eval "$(direnv hook bash)"' >> /etc/bash.bashrc \
    && add-apt-repository ppa:git-core/ppa \
    && apt-get install -y git \
    && curl -sL https://deb.nodesource.com/setup_14.x | bash - \
    && apt-get install -y nodejs=14.* \
    # the haxelib server code base is not Haxe 4 ready
    && add-apt-repository ppa:haxe/haxe3.4 \
    && add-apt-repository ppa:haxe/haxe4.2 \
    && apt-get install -y neko haxe=1:4.2.* \
    # Install mysql-client
    # https://github.com/docker-library/mysql/blob/master/5.7/Dockerfile.debian
    && echo 'deb http://repo.mysql.com/apt/ubuntu/ bionic mysql-5.7' > /etc/apt/sources.list.d/mysql.list \
    && apt-get update \
    && apt-get -y install mysql-client=5.7.* \
    # Install terraform
    && curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - \
    && apt-add-repository "deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    && apt-get -y install --no-install-recommends terraform=1.0.6 terraform-ls \
    && echo 'complete -C /usr/bin/terraform terraform' >> /etc/bash.bashrc \
    # install kubectl
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get -y install --no-install-recommends kubectl \
    && echo 'source <(kubectl completion bash)' >> /home/vscode/.bashrc \
    #
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g yarn

# Install AWS cli
RUN cd / \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf ./aws awscliv2.zip

# install aws-iam-authenticator
RUN curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/aws-iam-authenticator \
    && chmod +x ./aws-iam-authenticator \
    && mv ./aws-iam-authenticator /usr/local/bin/

# Config direnv
COPY --chown=$USER_UID:$USER_GID direnv.toml /home/$USERNAME/.config/direnv/config.toml

ENV YARN_CACHE_FOLDER=/yarn
RUN mkdir -m 777 "$YARN_CACHE_FOLDER"
RUN mkdir -m 777 "/workspace"
USER $USER_UID
WORKDIR /workspace
COPY --chown=$USER_UID:$USER_GID workspace/package.json workspace/yarn.lock /workspace/
RUN yarn
COPY --chown=$USER_UID:$USER_GID workspace/generate_extern.sh /workspace/
RUN ./generate_extern.sh
COPY --chown=$USER_UID:$USER_GID workspace/libs.hxml workspace/run.n /workspace/
COPY --chown=$USER_UID:$USER_GID workspace/lib /workspace/lib
RUN mkdir -p /workspace/haxelib_global
RUN haxelib setup /workspace/haxelib_global
RUN haxe libs.hxml && rm /workspace/haxelib_global/*.zip
VOLUME /workspace/node_modules /workspace/haxelib_global /workspace/lib/dts2hx-generated
USER root

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=

# Setting the ENTRYPOINT to docker-init.sh will configure non-root access 
# to the Docker socket. The script will also execute CMD as needed.
ENTRYPOINT [ "/usr/local/share/docker-init.sh" ]
CMD [ "sleep", "infinity" ]
