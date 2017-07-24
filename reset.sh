rm -rf /usr/local/bin/ssr
cd /usr/local
rm -rf SSR-Bash
git clone https://github.com/BBenQi/SSR-Bash
wget -N --no-check-certificate -O /usr/local/bin/ssr https://raw.githubusercontent.com/BBenQi/SSR-Bash/master/ssr
chmod +x /usr/local/bin/ssr