FROM quay.io/frrouting/frr:8.5.7 as base
RUN echo -e '\
export ASN_METALLB_LOCAL=4200099998 \n\
export ASN_METALLB_REMOTE=4200099999 \n\
export NAMESPACE_METALLB=metallb \n\
export PEER_IP_LOCAL=192.168.250.254 \n\
export PEER_IP_REMOTE=192.168.250.255 \n\
export PEER_IP_PREFIX=31 \n\
export PEER_IPV6_LOCAL=fdae:6bef:5e65::1 \n\
export PEER_IPV6_REMOTE=fdae:6bef:5e65::2 \n\
export PEER_IPV6_PREFIX=126 \n\
export INTERFACE_MTU=1500 \
' > /etc/frr/env.sh
COPY docker-start /usr/lib/frr/docker-start
COPY daemons /etc/frr/daemons
COPY frr.conf.j2 /etc/frr/frr.conf.j2
COPY neighbors.json /etc/frr/neighbors.json
RUN apk add --no-cache --update-cache gettext py3-pip iputils busybox-extras jq
RUN pip3 install j2cli
RUN chmod 755 /usr/lib/frr/docker-start
#RUN source /etc/frr/env.sh && j2 -o /usr/lib/frr/docker-start /usr/lib/frr/docker-start.j2


FROM scratch AS frr
COPY --from=base / /rootfs/usr/local/lib/containers/frr/
COPY frr.yaml /rootfs/usr/local/etc/containers/frr.yaml
COPY manifest.yaml /manifest.yaml

