FROM quay.io/frrouting/frr:10.4.1 AS base

# Install dependencies
RUN apk add --no-cache --update-cache gettext iputils busybox-extras jq python3 py3-yaml py3-jinja2

# Copy configuration loader and template renderer
COPY config_loader.py /usr/local/bin/config_loader.py
COPY render_template.py /usr/local/bin/render_template.py
RUN chmod +x /usr/local/bin/config_loader.py /usr/local/bin/render_template.py

# Copy default configuration template
COPY examples/config-bfd.yaml /etc/frr/config.default.yaml

# Copy FRR template
COPY frr.conf.j2 /etc/frr/frr.conf.j2

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

# Backup original /etc/frr for initialization on first boot
RUN cp -r /etc/frr /etc/frr.defaults

# Create a version file for tracking
RUN echo "FRR Extension v1.2.3 (FRR 10.4.1) - Talos ExtensionServiceConfig Integration" > /etc/frr/version

FROM scratch AS frr
COPY --from=base / /rootfs/usr/local/lib/containers/frr/
COPY frr.yaml /rootfs/usr/local/etc/containers/frr.yaml
COPY manifest.yaml /manifest.yaml