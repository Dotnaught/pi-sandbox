# Pin to a digest once stable: docker/sandbox-templates:shell@sha256:<digest>
FROM docker/sandbox-templates:shell

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg fd-find socat && \
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    curl -fsSL https://deb.nodesource.com/setup_26.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

USER agent
# Pin to an exact version for reproducible builds: @mariozechner/pi-coding-agent@<version>
RUN npm install -g @mariozechner/pi-coding-agent

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ~/.local/bin/uv tool install ruff
