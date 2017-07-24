#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

#Check Root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

#Set DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

#Disable selinux
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi

clear

#InstallBasicPackages
apt-get update -y
apt-get install git tar python unzip bc python-m2crypto curl wget unzip gcc swig automake make perl cpio build-essential -y
apt-get install language-pack-zh-hans -y


#Clone Something
cd /usr/local
git clone https://github.com/breakwa11/shadowsocks
git clone https://github.com/BBenQi/SSR-Bash

#Intall libsodium
cd /root
wget --no-check-certificate -O libsodium-1.0.10.tar.gz https://github.com/jedisct1/libsodium/releases/download/1.0.10/libsodium-1.0.10.tar.gz
tar -xf libsodium-1.0.10.tar.gz && cd libsodium-1.0.10
./configure && make && make install
echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig
cd ../ && rm -rf libsodium* 

#Install ssr-chkconfig
wget -N --no-check-certificate -O /etc/init.d/shadowsocksr https://raw.githubusercontent.com/BBenQi/SSR-Bash/blob/master/ssr-chkconfig
chmod +x /etc/init.d/shadowsocksr
update-rc.d -f shadowsocksr defaults

#Install Softlink
wget -N --no-check-certificate -O /usr/local/bin/ssr https://raw.githubusercontent.com/BBenQi/SSR-Bash/blob/master/ssr
chmod +x /usr/local/bin/ssr

echo '安装完成！输入 ssr 即可使用本程序~'
echo '欢迎加QQ群：277717865 讨论交流哦~'
