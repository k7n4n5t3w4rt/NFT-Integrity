FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    curl \
    wget \
    ca-certificates \
    make \
    locales \
    software-properties-common \
    ripgrep \
    fd-find \
    vim \
    netcat-openbsd \
    ngircd \
    irssi \
    tmux \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Configure UTF-8 locale
RUN sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

# Install Node.js (required for pi, Hardhat, etc.)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install pi globally
RUN npm install -g @earendil-works/pi-coding-agent

# Clone pi configuration repo to ~/.pi (overwrites any default config)
# Uses HTTPS for build-time access (no SSH key needed)
RUN git clone --depth 1 https://github.com/k7n4n5t3w4rt/pi.git /root/.pi

# Install Foundry for Solidity development
ENV HOME=/root
RUN curl -L https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup

ENV PATH="/root/.foundry/bin:$PATH"

# Configure ngircd for agent coordination chat
RUN mkdir -p /var/run/ngircd && chown nobody:nogroup /var/run/ngircd
COPY ngircd.conf /etc/ngircd/ngircd.conf

WORKDIR /workspaces/nft-contract
