# shellcheck shell=bash
# Install the one-shot first-boot service for steps that need a running
# system: ufw rules, libvirt network, power profile, Tailscale operator,
# GE-Proton retry, Ollama model pull.

flag() { is_true "$1" && echo true || echo false; }
model=""
is_true "$INSTALL_OLLAMA" && model="$OLLAMA_MODEL"
write_file /etc/cachy-firstboot.conf <<EOF
USERNAME="$USERNAME"
PERFORMANCE_PROFILE=$(flag "$PERFORMANCE_PROFILE")
INSTALL_GE_PROTON=$(flag "$INSTALL_GE_PROTON")
OLLAMA_MODEL="$model"
EOF
install_file firstboot/cachy-firstboot.sh /usr/local/lib/cachy-setup/cachy-firstboot.sh 0755
install_file firstboot/cachy-firstboot.service /etc/systemd/system/cachy-firstboot.service 0644
rm -f /var/lib/cachy-setup/firstboot.done
svc_enable cachy-firstboot.service
ok "first-boot service installed"
