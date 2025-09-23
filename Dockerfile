FROM quay.io/frrouting/frr:8.5.7 as base

# Install dependencies
RUN apk add --no-cache --update-cache gettext py3-pip iputils busybox-extras jq python3 py3-yaml
RUN pip3 install j2cli pyyaml

# Copy configuration loader
COPY config_loader.py /usr/local/bin/config_loader.py
RUN chmod +x /usr/local/bin/config_loader.py

# Copy default configuration template
COPY examples/config-bfd.yaml /etc/frr/config.default.yaml

# Copy FRR templates (standard, BFD, and multi-peer)
COPY frr.conf.j2 /etc/frr/frr.conf.j2
COPY frr-bfd.conf.j2 /etc/frr/frr-bfd.conf.j2
COPY frr-multipeer.conf.j2 /etc/frr/frr-multipeer.conf.j2

# No environment variables needed - everything comes from config files

# Copy startup script
COPY docker-start /usr/lib/frr/docker-start
RUN chmod 755 /usr/lib/frr/docker-start

# Copy FRR daemon configuration with BFD enabled
COPY daemons /etc/frr/daemons

# Ensure BFD daemon is enabled
RUN sed -i 's/^bfdd=.*/bfdd=true/' /etc/frr/daemons || echo "bfdd=true" >> /etc/frr/daemons
RUN sed -i 's/^bfdd_options=.*/bfdd_options="-A 127.0.0.1"/' /etc/frr/daemons || echo 'bfdd_options="-A 127.0.0.1"' >> /etc/frr/daemons

# Create directory for local config overrides
RUN mkdir -p /etc/frr/config.d

# Create a version file for tracking
RUN echo "FRR Extension v2.0 - Config File Only" > /etc/frr/version

FROM scratch AS frr
COPY --from=base / /rootfs/usr/local/lib/containers/frr/
COPY frr.yaml /rootfs/usr/local/etc/containers/frr.yaml
COPY manifest.yaml /manifest.yaml