%define debug_package %{nil}
Name:           alteeve-striker
Version:        3.0
Release:        1%{?dist}
Summary:        Alteeve Anvil! Striker dashboard


License:        GPLv2+
URL:            https://github.com/Seneca-CDOT/anvil
Source0:        https://github.com/Seneca-CDOT/anvil/archive/network-scan.tar.gz
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

%description
Web interface of the Striker dashboard for Alteeve Anvil! systems


%prep
%autosetup -n anvil-network-scan


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
mv %{buildroot}/%{_sbindir}/words.xml %{buildroot}/%{_datarootdir}/words.xml
%make_install


%files
%doc README.md notes
%config(noreplace) %{_sysconfdir}/anvil/anvil.conf
%{_sbindir}/*
%{_datarootdir}/perl5/Anvil/*
%{_datarootdir}/anvil.sql
%{_datarootdir}/words.xml
%{_var}/www/*
%{_usr}/lib/systemd/system/anvil-daemon.service


%changelog
* Fri Jan 26 2018 Matthew Marangoni <matthew.marangoni@senecacollege.ca> 3.0-1
- Initial RPM release
