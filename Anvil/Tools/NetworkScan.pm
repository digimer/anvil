#!/usr/bin/perl
#
# This scans the BCN looking for devices we know about to help automate the
# configuration of an Anvil!'s foundation pack.

package Anvil::Tools::NetworkScan;

use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Anvil::Tools::Vendors;

our $VERSION  = "3.0.0";
my $THIS_FILE = "Get.pm";

### Methods;
# scan
# save_scan_to_db

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::NetworkScan

Provides all methods related to scanning the network with nmap.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();

 # Access to methods using '$anvil->Get->X'.
 #
 # Example using 'scan()';
 $anvil->NetworkScan->scan({...});

=head1 METHODS

Methods in this module;

=cut
sub new
{
	my $class = shift;
	my $self  = {};

	bless $self, $class;

	return ($self);
}

# Get a handle on the Anvil::Tools object. I know that technically that is a sibling module, but it makes more
# sense in this case to think of it as a parent.
sub parent
{
	my $self   = shift;
	my $parent = shift;

	$self->{HANDLE}{TOOLS} = $parent if $parent;

	# Defend against memory leads. See Scalar::Util'.
	if (not isweak($self->{HANDLE}{TOOLS}))
	{
		weaken($self->{HANDLE}{TOOLS});;
	}

	return ($self->{HANDLE}{TOOLS});
}

#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################

=head2 scan

Scans a subnet using nmap. Uses all octets of an IP plus CIDR, and then does a scan. 
The amount of forks made depends on the CIDR value, then a /24 nmap scan is performed on each fork.

=head2 Parameters;

=head3 subnet

An IP address with CIDR.

Example: "10.20.0.0/16"

=cut
sub scan
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;

	my $subnet = defined $parameter->{subnet} ? $parameter->{subnet} : "";

	$anvil->data->{scan} = {
		ip		=>	{},
		path		=>	{
			child_output	=>	"/tmp/anvil-scan-network" . ".$$",
			nmap		=>	"/usr/bin/nmap",
			rm		=>	"/bin/rm",
		},
		sys		=>	{
			nmap_switches	=>	"-sP -PR --host-timeout 7s -T4",
			time_per_nmap_fork => 50, # In milliseconds
			quiet		=>	1,
			network		=>	$subnet,
		}
	};

	$anvil->NetworkScan->_get_ips();
	Anvil::Tools::Vendors::load($anvil->data->{scan});
	$anvil->NetworkScan->_scan_nmap_with_forks();
	$anvil->NetworkScan->_compile_nmap_results();
	$anvil->NetworkScan->_cleanup_temp();
	print "Network scan finished at: [".$anvil->NetworkScan->_get_date({use_time => time})."]\n" if not $anvil->data->{scan}{sys}{quiet};
}

=head2 save_scan_to_db

Saves a list of scan results to the database.

The IP, UUID, MAC Address, and Vendor information are
saved into the table bcn_scan_results

=cut
sub save_scan_to_db
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;

	$anvil->Database->connect();

	foreach my $this_ip (sort {$a cmp $b} keys %{$anvil->data->{scan}{ip}})
	{
		my $scan_uuid = "";

		# Check if an entry already exists at that IP address.
		my $query = "
SELECT
    bcn_scan_result_uuid
FROM
    bcn_scan_results
WHERE
    bcn_scan_result_ip = ".$anvil->data->{sys}{use_db_fh}->quote($this_ip)."
;";

		my $query_results = $anvil->Database->query({query => $query});
		foreach my $row (@{$query_results})
		{
			$scan_uuid = $row->[0];
		}

		if (not $scan_uuid)
		{
			$scan_uuid = $anvil->Get->uuid();

			# If an entry does not exist, insert the scan result to the database.
			my $query = "
INSERT INTO
    bcn_scan_results
(
		bcn_scan_result_uuid,
		bcn_scan_result_mac,
		bcn_scan_result_ip,
		bcn_scan_result_vendor,
		modified_date
) VALUES (
    ".$anvil->data->{sys}{use_db_fh}->quote($scan_uuid).",
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{scan}{ip}{$this_ip}{mac}).",
    ".$anvil->data->{sys}{use_db_fh}->quote($this_ip).",
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{scan}{ip}{$this_ip}{oem}).",
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{db_timestamp})."
);";
			$anvil->Database->write({query => $query});
		}
		else
		{
			# If an entry with that IP does exist in the database, update it to the current device/time from this scan result.
			my $query = "
UPDATE
    bcn_scan_results
SET
    bcn_scan_result_mac     = ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{scan}{ip}{$this_ip}{mac}).",
    bcn_scan_result_vendor  = ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{scan}{ip}{$this_ip}{oem}).",
    modified_date           = ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{db_timestamp})."
WHERE
    bcn_scan_result_uuid    = ".$anvil->data->{sys}{use_db_fh}->quote($scan_uuid)."
";
			$anvil->Database->write({query => $query});
		}
	}

	$anvil->Database->disconnect();
}

# =head3
#
# Private Functions;
#
# =cut

#############################################################################################################
# Private functions                                                                                         #
#############################################################################################################

=head2 _scan_nmap_with_forks

Splits an IP using the CIDR value to determine the amount of forks. Each fork process performs a /24 nmap 
scan for speed. Stores each result into separate files to be compiled after everything is done.

=cut
sub _scan_nmap_with_forks
{
	my $self      = shift;
	my $anvil     = $self->parent;

	# Create the directory where the child processes will write their output to.
	print "Scanning for devices on " . $anvil->data->{scan}{sys}{network} . " now:\n" if not $anvil->data->{scan}{sys}{quiet};
	print "# Network scan started at: [".$anvil->NetworkScan->_get_date({use_time => time})."], expected finish: [".$anvil->NetworkScan->_get_date({use_time => time + 300})."]\n" if not $anvil->data->{scan}{sys}{quiet};
	if (not -d $anvil->data->{scan}{path}{child_output})
	{
		mkdir $anvil->data->{scan}{path}{child_output} or die "Failed to create the temporary output directory: [" . $anvil->data->{scan}{path}{child_output} . "]\n";
		print "- Created the directory: [" . $anvil->data->{scan}{path}{child_output} . "] where child processes will record their output.\n" if not $anvil->data->{scan}{sys}{quiet};
	}
	else
	{
		# Clear out any files from the previous run
		$anvil->NetworkScan->_cleanup_temp();
	}

	### WARNING: Some switches might think this is a flood and get angry with us!
	# A straight nmap call of all 65,636 IPs on a /16 takes about 40+ minutes. So
	# to speed things up, we break it into 256 jobs, each scanning 256 IPs. Each
	# child process is told to wait ($i * $anvil->data->{scan}{sys}{time_per_nmap_fork}) seconds, where $i is equal to its segment
	# value. This is done to avoid running out of buffer, which causes output like:
	# WARNING:  eth_send of ARP packet returned -1 rather than expected 42 (errno=105: No buffer space available)
	# By staggering the child processes, we have early children exiting as new
	# children are spawned, and things are OK.
	my $parent_pid = $$;
	my %pids;
	my ($ipaddr, $cidr) = split(/\/(\d+$)/, $anvil->data->{scan}{sys}{network}, 2);
        my $netmask = (2**32)-1 & ~(2**(32-$cidr)-1);
        my ($octetA, $octetB, $octetC, $octetD) = split(/\./, $ipaddr);
        $octetA = $octetA * (2**24);
        $octetB = $octetB * (2**16);
        $octetC = $octetC * (2**8);
        my $numericIP = $octetA + $octetB + $octetC + $octetD;
	my $sleep_segment = 0;
  	for (my $i = $numericIP & $netmask; $i <= ((($numericIP & $netmask) | (~$netmask & ~255)) & 2**32-1); $i += 256)
	{
		$sleep_segment++;
		defined(my $pid = fork) or die "Can't fork(), error was: $!\n";
		if ($pid)
		{
			# Parent thread.
			$pids{$pid} = 1;
			#print "Spawned child with PID: [$pid].\n";
		}
		else
		{
			my $octet0 = "0/24";
      			my $octet1 = ($i >> 8) & 255;
      			my $octet2 = ($i >> 16) & 255;
      			my $octet3 = ($i >> 24) & 255;
			# This is the child thread, so do the call.
			# Note that, without the 'die', we could end
			# up here if the fork() failed.
			sleep(($sleep_segment * $anvil->data->{scan}{sys}{time_per_nmap_fork}) / 1000);
			my $output_file = $anvil->data->{scan}{path}{child_output} . "/segment.$sleep_segment.out";
			my $scan_range  = "$octet3".".$octet2".".$octet1".".$octet0";
			my $shell_call  = $anvil->data->{scan}{path}{nmap} . " " . $anvil->data->{scan}{sys}{nmap_switches} . " $scan_range > $output_file";
			print "Child process with PID: [$$] scanning segment: [$scan_range] now...\n" if not $anvil->data->{scan}{sys}{quiet};
			#print "Calling: [$shell_call]\n";
			open (my $file_handle, "$shell_call 2>&1 |") or die "Failed to call: [$shell_call], error was: $!\n";
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				print "PID: [$$], line: [$line]\n" if not $anvil->data->{scan}{sys}{quiet};
			}
			close $file_handle;


			# Kill the child process.
			exit;
		}
	}
	# Now loop until both child processes are dead.
	# This helps to catch hung children.
	my $saw_reaped = 0;

	# If I am here, then I am the parent process and all the child process have
	# been spawned. I will not enter a while() loop that will exist for however
	# long the %pids hash has data.
	while (%pids)
	{
		# This is a bit of an odd loop that put's the while()
		# at the end. It will cycle once per child-exit event.
		my $pid;
		do
		{
			# 'wait' returns the PID of each child as they
			# exit. Once all children are gone it returns
			# '-1'.
			$pid = wait;
			if ($pid < 1)
			{
				print "Parent process thinks all children are gone now as wait returned: [$pid]. Exiting loop.\n" if not $anvil->data->{scan}{sys}{quiet};
			}
			else
			{
				print "Parent process told that child with PID: [$pid] has exited.\n" if not $anvil->data->{scan}{sys}{quiet};
			}

			# This deletes the just-exited child process' PID from the
			# %pids hash.
			delete $pids{$pid};
		}
		while $pid > 0;	# This re-enters the do() loop for as
				# long as the PID returned by wait()
				# was >0.
	}
	print "Done, compiling results...\n" if not $anvil->data->{scan}{sys}{quiet};
}

=head2 _compile_nmap_results

Gets the data from the files created from each of the nmap calls and
compiles it into a hash.

=cut
sub _compile_nmap_results
{
	my $self      = shift;
	my $anvil     = $self->parent;

	my $this_ip  = "";
	my $this_mac = "";
	my $this_oem = "";
	local(*DIRECTORY);
	opendir(DIRECTORY, $anvil->data->{scan}{path}{child_output});
	while(my $file = readdir(DIRECTORY))
	{
		next if $file eq ".";
		next if $file eq "..";
		my $path       = $anvil->data->{scan}{path}{child_output} . "/$file";
		my $shell_call = "<$path";
		open (my $file_handle, "$shell_call") or die "Failed to read: [$shell_call], error was: $!\n";
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			print "line: [$line]\n" if not $anvil->data->{scan}{sys}{quiet};
			if ($line =~ /Nmap scan report for (\d+\.\d+\.\d+\.\d+)/)
			{
				$this_ip = $1;
			}
			elsif ($line =~ /scan report/)
			{
				# This shouldn't be hit...
				$this_ip = "";
			}
			if ($line =~ /MAC Address: ([0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2}) \((.*?)\)/)
			{
				$this_mac = $1;
				$this_oem = $2;
			}
			if (($this_ip) && ($this_mac) && ($this_oem))
			{
				$anvil->data->{scan}{ip}{$this_ip}{mac} = $this_mac;
				$anvil->data->{scan}{ip}{$this_ip}{oem} = $this_oem;
			}
		}
		close $file_handle;
	}
	print "Done.\n\n" if not $anvil->data->{scan}{sys}{quiet};

	print "Discovered IPs:\n" if not $anvil->data->{scan}{sys}{quiet};
	foreach my $this_ip (sort {$a cmp $b} keys %{$anvil->data->{scan}{ip}})
	{
		if ($anvil->data->{scan}{ip}{$this_ip}{oem} =~ /Unknown/i)
		{
			my $short_mac = lc(($anvil->data->{scan}{ip}{$this_ip}{mac} =~ /^([0-9A-F]{2}:[0-9A-F]{2}:[0-9A-F]{2})/)[0]);
			$anvil->data->{scan}{ip}{$this_ip}{oem} = $anvil->data->{scan}{vendors}{$short_mac} ? $anvil->data->{scan}{vendors}{$short_mac} : "--";
		}

		print "- IP: [$this_ip]\t-> [" . $anvil->data->{scan}{ip}{$this_ip}{mac} . "] (" . $anvil->data->{scan}{ip}{$this_ip}{oem} . ")\n" if not $anvil->data->{scan}{sys}{quiet};
	}
}

=head2 _cleanup_temp

Gets the data from the files created from each of the nmap calls and
compiles it into a hash.

=cut
sub _cleanup_temp
{
	my $self      = shift;
	my $anvil     = $self->parent;

	print "- Purging old scan files.\n" if not $anvil->data->{scan}{sys}{quiet};
	system($anvil->data->{scan}{path}{rm}, "-rf", $anvil->data->{scan}{path}{child_output});
}

=head2 _get_date

This returns the current date and time in 'YYYY/MM/DD HH:MM:SS' format. It
always uses 24-hour time and it zero-pads single digits.

=cut
sub _get_date
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $use_time = defined $parameter->{use_time} ? $parameter->{use_time} : time;
	my $date     = "";

	# This doesn't support offsets or other advanced features.
	my %time;
	($time{sec}, $time{min}, $time{hour}, $time{mday}, $time{mon}, $time{year}, $time{wday}, $time{yday}, $time{isdst}) = localtime($use_time);

	# Increment the month by one.
	$time{mon}++;

	# 24h time.
	$time{pad_hour} = sprintf("%02d", $time{hour});
	$time{pad_min}  = sprintf("%02d", $time{min});
	$time{pad_sec}  = sprintf("%02d", $time{sec});
	$time{year}     = ($time{year} + 1900);
	$time{pad_mon}  = sprintf("%02d", $time{mon});
	$time{pad_mday} = sprintf("%02d", $time{mday});
	$time{mon}++;

	$date = "$time{year}/$time{pad_mon}/$time{pad_mday} $time{pad_hour}:$time{pad_min}:$time{pad_sec}";

	return($date);
}

=head2 _get_ips

Get all local ips and exclude them from the nmap scan.

=cut
sub _get_ips
{
	my $self      = shift;
	my $anvil     = $self->parent;

	$anvil->System->get_ips();
	my @ips;
	foreach my $interface (keys %{$anvil->data->{sys}{networks}})
	{
		if ($anvil->data->{sys}{networks}{$interface}{ip})
		{
			push @ips, $anvil->data->{sys}{networks}{$interface}{ip};
		}
	}
	$anvil->data->{scan}{sys}{host_ips} = \@ips;
	$anvil->data->{scan}{sys}{nmap_switches} .= " --exclude " . join(",", @ips);
}

1;
