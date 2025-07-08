#!/usr/bin/env bash

set -exuo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <NETEYE_VERSION>"
    exit 1
fi
export NETEYE_VERSION="$1"

cat <<'EOF' >/etc/yum.repos.d/NetEye.repo
[neteye]
name=NetEye
baseurl=https://repo.wuerth-phoenix.com/rhel8/neteye-$NETEYE_VERSION
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-NETEYE
enabled=0
priority=1
EOF

dnf config-manager --disable rhv-4-tools-for-rhel-8-x86_64-rpms
subscription-manager repo-override --repo=rhel-8-for-x86_64-appstream-rpms --add=exclude:grafana*
subscription-manager repos --enable rhel-8-for-x86_64-baseos-rpms \
    --enable codeready-builder-for-rhel-8-x86_64-rpms \
    --enable ansible-2-for-rhel-8-x86_64-rpms \
    --enable rhel-8-for-x86_64-highavailability-rpms \
    --enable openstack-15-tools-for-rhel-8-x86_64-rpms
dnf install @php:7.4 -y
dnf install @python36:3.6 -y
dnf update -y

dnf install -y neteye neteye-stable ansible --enablerepo=neteye
cp /neteye/local/os/conf/neteye_rpmmirrors_default/* /neteye/local/os/conf/customer_rpmmirrors/

neteye rpmmirror apply
dnf remove -y ansible

dnf clean metadata --enablerepo=*
dnf install -y @neteye-tools --enablerepo=neteye
dnf install -y @neteye --enablerepo=neteye

dnf clean metadata --enablerepo=*
dnf install -y selinux-policy-targeted --enablerepo=rhel-8-for-x86_64-baseos-rpms
dnf update -y --enablerepo=neteye

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
