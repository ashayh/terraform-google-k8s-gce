#!/bin/bash -xe

sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

yum -y install \
  epel-release \
  device-mapper-persistent-data \
  lvm2 \
  yum-utils

yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
      https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

network_plugin=kubenet
if [ "${pod_network_type}" == "calico" ]; then
  network_plugin=cni
fi

# Drop in config for kubenet and cloud provider
mkdir -p /etc/systemd/system/kubelet.service.d
cat > /etc/systemd/system/kubelet.service.d/20-gcenet.conf <<EOF
[Service]
Environment="KUBELET_NETWORK_ARGS=--network-plugin=$${network_plugin} --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=${dns_ip} --cluster-domain=cluster.local"
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=gce"
EOF

mkdir -p /etc/kubernetes
cat <<'EOF' > /etc/kubernetes/gce.conf
[global]
multizone = true
node-tags = ${tags}
node-instance-prefix = ${instance_prefix}
network-project-id = ${project_id}
network-name = ${network_name}
subnetwork-name = ${subnetwork_name}
${gce_conf_add}
EOF
cp /etc/kubernetes/gce.conf /etc/gce.conf

# kubeadm 1.8 workaround for https://github.com/kubernetes/release/issues/406
mkdir -p /etc/kubernetes/pki
cp /etc/kubernetes/gce.conf /etc/kubernetes/pki/gce.conf

# for GLBC
touch /var/log/glbc.log

mkdir /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "ipv6": true, "fixed-cidr-v6": "2001:db8:1::/64"
}
EOF

yum -y install -y \
  jq \
  nginx \
  docker-ce-${docker_version}* \
  kubernetes-cni-${cni_version}* \
  kubelet-${k8s_version}* \
  kubeadm-${k8s_version}* \
  kubectl-${k8s_version}* \

for f in kubelet kubeadm kubectl; do
  gsutil cp gs://kubernetes-release/release/v${k8s_version_override}/bin/linux/amd64/$f /usr/bin/$f
  chmod +x /usr/bin/$f
done

systemctl enable docker
sed -i 's#ExecStart=/usr/bin/dockerd.*#ExecStart=/usr/bin/dockerd --exec-opt native.cgroupdriver=systemd#' /etc/systemd/system/multi-user.target.wants/docker.service
systemctl restart docker
 
systemctl daemon-reload

systemctl enable nginx   ; systemctl restart nginx
systemctl enable kubelet ; systemctl restart kubeletcl
