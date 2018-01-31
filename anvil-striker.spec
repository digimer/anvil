%define debug_package %{nil}
Name:           anvil
Version:        3.0
Release:        1%{?dist}
Summary:        Alteeve Anvil! complete package


License:        GPLv2+
URL:            https://github.com/Seneca-CDOT/anvil
Source0:        https://github.com/Seneca-CDOT/anvil/archive/combined-branches.tar.gz
BuildArch:      noarch

Conflicts:      iptables-services

Requires:       perl-XML-Simple
Requires:       postgresql-server
Requires:       postgresql-plperl
Requires:       postgresql-contrib
Requires:       perl-CGI
Requires:       perl-NetAddr-IP
Requires:       perl-DBD-Pg
Requires:       rsync
Requires:       perl-Log-Journald
Requires:       perl-Net-SSH2
Requires:       httpd
Requires:       firewalld

%description
This package generates the anvil-core, anvil-striker, and anvil-node RPM's

%package core
Summary:        Alteeve Anvil! Core package
%description core
Common base libraries required for the Anvil! system

%package striker
Summary:        Alteeve Anvil! Striker dashboard package
%description striker
Web interface of the Striker dashboard for Alteeve Anvil! systems


#%package node
#Summary:        Alteeve Anvil! Node package
#%description node
#<placeholder for node description>


%prep
%autosetup -n anvil-combined-branches


%build


%install
rm -rf $RPM_BUILD_ROOT
mkdir -p %{buildroot}/usr/sbin/anvil/
mkdir -p %{buildroot}/etc/anvil/
mkdir -p %{buildroot}/var/www/
install -d -p Anvil %{buildroot}/usr/share/perl5/
install -d -p html %{buildroot}/var/www/
install -d -p cgi-bin %{buildroot}/var/www/
install -d -p units/ %{buildroot}/usr/lib/systemd/system/
install -d -p tools/ %{buildroot}/usr/sbin/
cp -R -p Anvil %{buildroot}/usr/share/perl5/
cp -R -p html %{buildroot}/var/www/
cp -R -p cgi-bin %{buildroot}/var/www/
cp -R -p units/* %{buildroot}/usr/lib/systemd/system/
cp -R -p tools/* %{buildroot}/usr/sbin/
cp -R -p anvil.conf %{buildroot}/etc/anvil/
mv %{buildroot}/%{_sbindir}/anvil.sql %{buildroot}/%{_datarootdir}/anvil.sql


%files core
%doc README.md notes
%config(noreplace) %{_sysconfdir}/anvil/anvil.conf
%config(noreplace) %{_datarootdir}/anvil.sql
%{_datarootdir}/*
%{_usr}/lib/*
%{_sbindir}/*


%files striker
%attr(0775, apache, anvil) %{_var}/www/*


#%files node
#<placeholder for node specific files>


%changelog
* Fri Jan 26 2018 Matthew Marangoni <matthew.marangoni@senecacollege.ca> 3.0-1
- Initial RPM release
