FROM openvpn/openvpn-as:latest

# Copy custom init script
COPY ./init-radius.sh /init-radius.sh

# Ensure it's executable
RUN chmod +x /init-radius.sh

RUN ln /var/log/openvpnas.log /var/log/openvpn/openvpnas.log

# Set default CMD that starts init in background and then OpenVPN
CMD ["/bin/bash", "-c", "/init-radius.sh & exec /usr/local/openvpn_as/scripts/openvpnas --nodaemon --pidfile=/ovpn/tmp/openvpn.pid"]
