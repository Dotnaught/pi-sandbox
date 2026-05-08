# Pin to a digest once stable: docker/sandbox-templates:shell@sha256:<digest>
FROM docker/sandbox-templates:shell

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg fd-find && \
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    curl -fsSL https://deb.nodesource.com/setup_26.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*
COPY pi-start.sh /usr/local/bin/pi-start.sh
RUN chmod +x /usr/local/bin/pi-start.sh
COPY --chown=agent:agent skills/ /home/agent/.pi/agent/skills/
COPY --chown=agent:agent CLAUDE.md /home/agent/.pi/agent/CLAUDE.md

USER agent
RUN npm install -g @earendil-works/pi-coding-agent@0.74.0

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ~/.local/bin/uv tool install ruff
