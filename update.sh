#!/bin/bash
#
# Title: Striker Dashboard v3 Updater
# Purpose: Update an installation of Alteeve's Striker Dashboard v3
# Author: Chris Johnson <chris.johnson@senecacollege.ca>
# Last Modified: November 10, 2017
#
# NOTE: This updater script is only compatible with the EL7-based v3.x generation of Anvil!

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

stop_services () {
	systemctl stop anvil-daemon
	systemctl stop httpd
	systemctl stop postgresql
}

update_anvil () {
	cd $gitLocal
	git pull
	cd -
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

# Reload and restart services
service_restart () {
	systemctl daemon-reload
	systemctl restart firewalld
	systemctl restart postgresql
	systemctl restart httpd
	systemctl restart anvil-daemon
}

# Function calls (main program sequence)
check_root
update_anvil
copy_anvil
al-repo_definitions
al-repo_packages
enable_epel_release
required_packages
sysadmin_tools
dbaddress_config
selinux_permissive
db_initialize
service_restart