FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash testuser \
    && echo 'testuser:Paramiko5-Test-Only!' | chpasswd \
    && mkdir -p /run/sshd /home/testuser/.ssh \
    && chown -R testuser:testuser /home/testuser/.ssh \
    && chmod 700 /home/testuser/.ssh \
    && ssh-keygen -A

COPY sshd_config /etc/ssh/sshd_config
COPY runtime/authorized_keys /home/testuser/.ssh/authorized_keys

RUN chown testuser:testuser /home/testuser/.ssh/authorized_keys \
    && chmod 600 /home/testuser/.ssh/authorized_keys \
    && /usr/sbin/sshd -t

EXPOSE 22

CMD ["sh", "-c", "rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && exec /usr/sbin/sshd -D -e"]
