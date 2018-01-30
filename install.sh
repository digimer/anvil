#!/bin/bash
#
# Title: Striker Dashboard v3 Installer
# Purpose: Download and install Striker Dashboard.
# Author: Chris Johnson <chris.johnson@senecacollege.ca>
# Last Modified: November 10, 2017

# Location definitions
gitURI=https://github.com/Seneca-CDOT/anvil.git
gitLocal=/root/anvil
alteeveRepo=https://www.alteeve.com/an-repo/el7

# IP Definitions
DB1=10.20.4.1
DB2=10.20.4.2

# Checks for root user.
check_root () {
	if [ "$USER" != "root" ]; then
    	printf "Must be root to run.\n\n"
    	exit
	fi
}

# Install firewalld, remove iptables-services if present
install_firewalld () {
	yum -y install firewalld
	yum -y remove iptables-services 2>/dev/null
}

# Install git and download v3 from GitHub
download_anvil () {
	yum -y install git
	mkdir $gitLocal
	git clone $gitURI $gitLocal
	cd $gitLocal
	git fetch
	git checkout network-scan
	cd -
}

# Create destination directories
create_dirs () {
	mkdir /usr/sbin/anvil/
	mkdir /etc/anvil/
	mkdir /var/www/
}

# Copy v3 software to destination directories
# Note: Download and copy done to preserve git tracking
copy_anvil () {
	cp -R $gitLocal/Anvil /usr/share/perl5/
	cp -R $gitLocal/html /var/www/
	cp -R $gitLocal/cgi-bin /var/www/
	cp -R $gitLocal/units/* /usr/lib/systemd/system/
	cp -R $gitLocal/tools/* /usr/sbin/anvil/
	cp -R $gitLocal/anvil.conf /etc/anvil/
	restorecon -rv /var/www
}

# Download Alteeve repository definitions
al-repo_definitions () {
	curl $alteeveRepo/alteeve-el7.repo -o /etc/yum.repos.d/alteeve-el7.repo
	curl $alteeveRepo/Alteeve-el7-GPG-KEY -o /etc/pki/rpm-gpg/Alteeve-el7-GPG-KEY
}

# Install all packages in Alteeve repo
al-repo_packages () {
	yum -y repo-pkgs alteeve-el7-repo install
}

# Enable epel-release repo
enable_epel_release () {
	yum -y install epel-release
}

# Install additional required packages
required_packages () {
	yum -y install perl-XML-Simple postgresql-server postgresql-plperl postgresql-contrib perl-CGI perl-NetAddr-IP perl-DBD-Pg rsync perl-Log-Journald perl-Net-SSH2 httpd nmap 'perl(SNMP)' 'perl(Net::SNMP)' 'perl(Device::SerialPort)' 'perl(Net::Telnet)'
}

# Install useful sysadmin/troubleshooting utilities
sysadmin_tools () {
	yum -y install net-tools bind-utils vim telnet tree
}

# Firewall Startup
firewall_start () {
	systemctl enable firewalld
	systemctl start firewalld
}

# Firewall Rules
firewall_rules () {
	firewall-cmd --permanent --add-service=http
	firewall-cmd --permanent --add-service=postgresql
	firewall-cmd --reload
}

# Apache Startup
httpd_start () {
	systemctl enable httpd
	systemctl start httpd
}

# PostgreSQL Enable
postgresql_enable () {
	systemctl enable postgresql
}

# Replace database IP addresses
dbaddress_config () {
	sed -i "s%192.168.122.201%$DB1%g" /etc/anvil/anvil.conf
	sed -i "s%192.168.122.202%$DB2%g" /etc/anvil/anvil.conf
}

# Set SELinux to permissive
selinux_permissive () {
	sed -i "s%^SELINUX=.*%SELINUX=permissive%g" /etc/selinux/config
	setenforce 0
}

# Initialize database
db_initialize () {
	postgresql-setup initdb
	$gitLocal/test.pl
}

# Start Anvil Daemon
anvil_start () {
	systemctl daemon-reload
	systemctl enable anvil-daemon
	systemctl start anvil-daemon
}

# Function calls (main program sequence)
check_root
install_firewalld
#download_anvil
create_dirs
copy_anvil
al-repo_definitions
al-repo_packages
enable_epel_release
required_packages
sysadmin_tools
firewall_start
firewall_rules
httpd_start
postgresql_enable
dbaddress_config
selinux_permissive
db_initialize
anvil_start