package Anvil::Tools::Alert;
# 
# This module contains methods used to handle alerts and errors.
# 

use strict;
use warnings;
use Scalar::Util qw(weaken isweak);

our $VERSION  = "3.0.0";
my $THIS_FILE = "Alert.pm";

### Methods;
# check_alert_sent
# error
# register_alert

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::Alert

Provides all methods related warnings and alerts.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();
 
 # Access to methods using '$anvil->Alert->X'. Example using 'find';
 my $foo_path = $anvil->Storage->find({file => "foo"});

=head1 METHODS

Methods in the core module;

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


=head2 check_alert_sent

This is used by scan agents that need to track whether an alert was sent when a sensor dropped below/rose above a set alert threshold. For example, if a sensor alerts at 20°C and clears at 25°C, this will be called when either value is passed. When passing the warning threshold, the alert is registered and sent to the user. Once set, no further warning alerts are sent. When the value passes over the clear threshold, this is checked and if an alert was previously registered, it is removed and an "all clear" message is sent. In this way, multiple alerts will not go out if a sensor floats around the warning threshold and a "cleared" message won't be sent unless a "warning" message was previously sent.

If there is a problem, C<< !!error!! >> is returned.

Parameters;

=head3 modified_date (optional)

By default, this is set to C<< sys::db_timestamp >>. If you want to force a different timestamp, you can do so with this parameter.

=head3 name (required)

This is the name of the alert. So for an alert related to a critically high temperature, this might get set to C<< temperature_high_critical >>. It is meant to compliment the C<< record_locator >> parameter.

=head3 record_locator

This is a record locator, which generally allows a given alert to be tied to a given source. For example, an alert related to a temperature might use C<< an-a01n01.alteeve.com:cpu1_temperature >>.

=head3 set_by (required)

This is a string, usually the name of the program, that set the alert. Usuall this is simple C<< $THIS_FILE >> or C<< $0 >>.

=head3 type (required)

This is set to C<< set >> or C<< clear >>.

If set to C<< set >>, C<< 1 >> will be returned if this is the first time we've tried to set this alert. If the alert was set before, C<< 0 >> is returned.

If set to C<< clear >>, C<< 1 >> will be returned if this is the alert existed and was cleared. If the alert didn't exist (and thus didn't need to be cleared), C<< 0 >> is returned.

=cut
sub check_alert_sent
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $debug          = defined $parameter->{debug}          ? $parameter->{debug}          : 3;
	my $modified_date  = defined $parameter->{modified_date}  ? $parameter->{modified_date}  : $anvil->data->{sys}{db_timestamp};
	my $name           = defined $parameter->{name}           ? $parameter->{name}           : "";
	my $record_locator = defined $parameter->{record_locator} ? $parameter->{record_locator} : "";
	my $set_by         = defined $parameter->{set_by}         ? $parameter->{set_by}         : "";
	my $type           = defined $parameter->{type}           ? $parameter->{type}           : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		modified_date  => $modified_date, 
		name           => $name, 
		record_locator => $record_locator, 
		set_by         => $set_by, 
		type           => $type, 
	}});
	
	# Do we have a timestamp?
	if (not $modified_date)
	{
		# Nope
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0093"});
		return("!!error!!");
	}
	
	# Do we have an alert name?
	if (not $name)
	{
		# Nope
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Alert->check_alert_sent()", parameter => "name" }});
		return("!!error!!");
	}
	
	# Do we have an record locator?
	if (not $record_locator)
	{
		# Nope
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Alert->check_alert_sent()", parameter => "record_locator" }});
		return("!!error!!");
	}
	
	# Do we know who is setting this??
	if (not $set_by)
	{
		# Nope
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Alert->check_alert_sent()", parameter => "set_by" }});
		return("!!error!!");
	}
	
	# Are we setting or clearing?
	if (not $type)
	{
		# Neither...
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0097"});
		return("!!error!!");
	}
	
	# This will get set to '1' if an alert is added or removed.
	my $set = 0;
	
	my $query = "
SELECT 
    alert_sent_uuid 
FROM 
    alert_sent 
WHERE 
    alert_sent_host_uuid = ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{host_uuid})." 
AND 
    alert_set_by         = ".$anvil->data->{sys}{use_db_fh}->quote($set_by)." 
AND 
    alert_record_locator = ".$anvil->data->{sys}{use_db_fh}->quote($record_locator)." 
AND 
    alert_name           = ".$anvil->data->{sys}{use_db_fh}->quote($name)."
;";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { query => $query }});
	
	# Now, if this is type=set, register the alert if it doesn't exist. If it is type=clear, remove the 
	# alert if it exists.
	my $alert_sent_uuid = $anvil->Database->query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
	   $alert_sent_uuid = "" if not defined $alert_sent_uuid;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		type            => $type,
		alert_sent_uuid => $alert_sent_uuid,
	}});
	if (($type eq "set") && (not $alert_sent_uuid))
	{
		### New alert
		# Make sure this host is in the database... It might not be on the very first run of ScanCore
		# before the peer exists (tried to connect to the peer, fails, tries to send an alert, but
		# this host hasn't been added because it is the very first attempt to connect...)
		if (not $anvil->data->{sys}{host_is_in_db})
		{
			my $query = "
SELECT 
    COUNT(*)
FROM 
    hosts 
WHERE 
    host_uuid = ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{host_uuid})."
;";
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { query => $query }});

			my $count = $anvil->Database->query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { count => $count }});
			
			if (not $count)
			{
				# Too early, we can't set an alert.
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0098", variables => {
					type           => $type, 
					set_by         => $set_by, 
					record_locator => $record_locator, 
					name           => $name, 
					modified_date  => $modified_date,
				}});
				return("!!error!!");
			}
			else
			{
				$anvil->data->{sys}{host_is_in_db} = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'sys::host_is_in_db' => $anvil->data->{sys}{host_is_in_db} }});
			}
		}
		
		   $set   = 1;
		my $query = "
INSERT INTO 
    alert_sent 
(
    alert_sent_uuid, 
    alert_sent_host_uuid, 
    alert_set_by, 
    alert_record_locator, 
    alert_name, 
    modified_date
) VALUES (
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->Get->uuid).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{host_uuid}).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($set_by).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($record_locator).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($name).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{db_timestamp})."
);
";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			query => $query,
			set   => $set, 
		}});
		$anvil->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	elsif (($type eq "clear") && ($alert_sent_uuid))
	{
		# Alert previously existed, clear it.
		   $set   = 1;
		my $query = "
DELETE FROM 
    alert_sent 
WHERE 
    alert_sent_uuid = ".$anvil->data->{sys}{use_db_fh}->quote($alert_sent_uuid)." 
;";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			query => $query,
			set   => $set, 
		}});
		$anvil->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { set => $set }});
	return($set);
}

=head2 register_alert

This registers an alert to be sent later.

If anything goes wrong, C<< !!error!! >> will be returned.

=cut
sub register_alert
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $header            = defined $parameter->{header}            ? $parameter->{header}            : 1;
	my $level             = defined $parameter->{level}             ? $parameter->{level}             : "warning";
	my $message_key       = defined $parameter->{message_key}       ? $parameter->{message_key}       : "";
	my $message_variables = defined $parameter->{message_variables} ? $parameter->{message_variables} : "";
	my $set_by            = defined $parameter->{set_by}            ? $parameter->{set_by}            : "";
	my $sort              = defined $parameter->{'sort'}            ? $parameter->{'sort'}            : 9999;
	my $title_key         = defined $parameter->{title_key}         ? $parameter->{title_key}         : "title_0003";
	my $title_variables   = defined $parameter->{title_variables}   ? $parameter->{title_variables}   : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		header            => $header,
		level             => $level, 
		message_key       => $message_key, 
		message_variables => $message_variables, 
		set_by            => $set_by,
		'sort'            => $sort, 
		title_key         => $title_key, 
		title_variables   => $title_variables, 
	}});
	
	if (not $set_by)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Alert->register_alert()", parameter => "set_by" }});
		return("!!error!!");
	}
	if (not $message_key)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Alert->register_alert()", parameter => "message_key" }});
		return("!!error!!");
	}
	if (($header) && (not $title_key))
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0101"});
		return("!!error!!");
	}
	
	# zero-pad sort numbers so that they sort properly.
	$sort = sprintf("%04d", $sort);
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { alert_sort => $sort }});
	
	# Convert the hash of title variables and message variables into '!!x!y!!,!!a!b!!,...' strings.
	if (ref($title_variables) eq "HASH")
	{
		foreach my $key (sort {$a cmp $b} keys %{$title_variables})
		{
			$title_variables->{$key} = "--" if not defined $title_variables->{$key};
			$title_variables .= "!!$key!".$title_variables->{$key}."!!,";
		}
	}
	if (ref($message_variables) eq "HASH")
	{
		foreach my $key (sort {$a cmp $b} keys %{$message_variables})
		{
			$message_variables->{$key} = "--" if not defined $message_variables->{$key};
			$message_variables .= "!!$key!".$message_variables->{$key}."!!,";
		}
	}
	
	
	# In most cases, no one is listening to 'debug' or 'info' level alerts. If that is the case here, 
	# don't record the alert because it can cause the history.alerts table to grow needlessly. So find
	# the lowest level log level actually being listened to and simply skip anything lower than that.
	# 5 == debug
	# 1 == critical
	my $lowest_log_level = 5;
	foreach my $integer (sort {$a cmp $b} keys %{$anvil->data->{alerts}{recipient}})
	{
		# We want to know the alert level, regardless of whether the recipient is an email of file 
		# target.
		my $this_level;
		if ($anvil->data->{alerts}{recipient}{$integer}{email})
		{
			# Email recipient
			$this_level = ($anvil->data->{alerts}{recipient}{$integer}{email} =~ /level="(.*?)"/)[0];
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { this_level => $this_level }});
		}
		elsif ($anvil->data->{alerts}{recipient}{$integer}{file})
		{
			# File target
			$this_level = ($anvil->data->{alerts}{recipient}{$integer}{file} =~ /level="(.*?)"/)[0];
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { this_level => $this_level }});
		}
		
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { this_level => $this_level }});
		if ($this_level)
		{
			$this_level = $anvil->Alert->convert_level_name_to_number({level => $this_level});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				this_level       => $this_level,
				lowest_log_level => $lowest_log_level,
			}});
			if ($this_level < $lowest_log_level)
			{
				$lowest_log_level = $this_level;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { lowest_log_level => $lowest_log_level }});
			}
		}
	}
	
	# Now get the numeric value of this alert and return if it is higher.
	my $this_level = $anvil->Alert->convert_level_name_to_number({level => $level});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		alert_level      => $level,
		this_level       => $this_level,
		lowest_log_level => $lowest_log_level,
	}});
	if ($this_level > $lowest_log_level)
	{
		# Return.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0102", variables => { message_key => $message_key }});
		return(0);
	}
	
	# Always INSERT. ScanCore removes them as they're acted on (copy is left in history.alerts).
	my $query = "
INSERT INTO 
    alerts
(
    alert_uuid, 
    alert_host_uuid, 
    alert_set_by, 
    alert_level, 
    alert_title_key, 
    alert_title_variables, 
    alert_message_key, 
    alert_message_variables, 
    alert_sort, 
    alert_header, 
    modified_date
) VALUES (
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->Get->uuid()).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{host_uuid}).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($set_by).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($level).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($title_key).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($title_variables).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($message_key).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($message_variables).",
    ".$anvil->data->{sys}{use_db_fh}->quote($sort).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($header).", 
    ".$anvil->data->{sys}{use_db_fh}->quote($anvil->data->{sys}{db_timestamp})."
);
";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
	$anvil->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
	
	return(0);
}

=head2 error

=cut

# Later, this will support all the translation and logging methods. For now, just print the error and exit.
sub error
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
# 	$anvil->Log->entry({log_level => 2, title_key => "tools_log_0001", title_variables => { function => "error" }, message_key => "tools_log_0002", file => $THIS_FILE, line => __LINE__});
# 	
# 	# Setup default values
# 	my $title_key         = $parameter->{title_key}         ? $parameter->{title_key}         : $anvil->String->get({key => "an_0004"});
# 	my $title_variables   = $parameter->{title_variables}   ? $parameter->{title_variables}   : "";
# 	my $message_key       = $parameter->{message_key}       ? $parameter->{message_key}       : $anvil->String->get({key => "an_0005"});
# 	my $message_variables = $parameter->{message_variables} ? $parameter->{message_variables} : "";
# 	my $code              = $parameter->{code}              ? $parameter->{code}              : 1;
# 	my $file              = $parameter->{file}              ? $parameter->{file}              : $anvil->String->get({key => "an_0006"});
# 	my $line              = $parameter->{line}              ? $parameter->{line}              : "";
# 	#print "$THIS_FILE ".__LINE__."; title_key: [$title_key], title_variables: [$title_variables], message_key: [$message_key], message_variables: [$message_variables], code: [$code], file: [$file], line: [$line]\n";
# 	
# 	# It is possible for this to become a run-away call, so this helps
# 	# catch when that happens.
# 	$anvil->_error_count($anvil->_error_count + 1);
# 	if ($anvil->_error_count > $anvil->_error_limit)
# 	{
# 		print "Infinite loop detected while trying to print an error:\n";
# 		print "- title_key:         [$title_key]\n";
# 		print "- title_variables:   [$title_variables]\n";
# 		print "- message_key:       [$message_key]\n";
# 		print "- message_variables: [$title_variables]\n";
# 		print "- code:              [$code]\n";
# 		print "- file:              [$file]\n";
# 		print "- line:              [$line]\n";
# 		die "Infinite loop detected while trying to print an error, exiting.\n";
# 	}
# 	
# 	# If the 'code' is empty and 'message' is "error_\d+", strip that code
# 	# off and use it as the error code.
# 	#print "$THIS_FILE ".__LINE__."; code: [$code], message_key: [$message_key]\n";
# 	if ((not $code) && ($message_key =~ /error_(\d+)/))
# 	{
# 		$code = $1;
# 		#print "$THIS_FILE ".__LINE__."; code: [$code], message_key: [$message_key]\n";
# 	}
# 	
# 	# If the title is a key, translate it.
# 	#print "$THIS_FILE ".__LINE__."; title_key: [$title_key]\n";
# 	if ($title_key =~ /\w+_\d+$/)
# 	{
# 		$title_key = $anvil->String->get({
# 			key		=>	$title_key,
# 			variables	=>	$title_variables,
# 		});
# 		#print "$THIS_FILE ".__LINE__."; title_key: [$title_key]\n";
# 	}
# 	
# 	# If the message is a key, translate it.
# 	#print "$THIS_FILE ".__LINE__."; message_key: [$message_key]\n";
# 	if ($message_key =~ /\w+_\d+$/)
# 	{
# 		$message_key = $anvil->String->get({
# 			key		=>	$message_key,
# 			variables	=>	$message_variables,
# 		});
# 		#print "$THIS_FILE ".__LINE__."; message_key: [$message_key]\n";
# 	}
# 	
# 	# Set my error string
# 	my $fatal_heading = $anvil->String->get({key => "an_0002"});
# 	#print "$THIS_FILE ".__LINE__."; fatal_heading: [$fatal_heading]\n";
# 	
# 	my $readable_line = $anvil->Readable->comma($line);
# 	#print "$THIS_FILE ".__LINE__."; readable_line: [$readable_line]\n";
# 	
# 	### TODO: Copy this to 'warning'.
# 	# At this point, the title and message keys are the actual messages.
# 	my $error = "\n".$anvil->String->get({
# 		key		=>	"an_0007",
# 		variables	=>	{
# 			code		=>	$code,
# 			heading		=>	$fatal_heading,
# 			file		=>	$file,
# 			line		=>	$readable_line,
# 			title		=>	$title_key,
# 			message		=>	$message_key,
# 		},
# 	})."\n\n";
# 	#print "$THIS_FILE ".__LINE__."; error: [$error]\n";
# 	
# 	# Set the internal error flags
# 	$anvil->Alert->_set_error($error);
# 	$anvil->Alert->_set_error_code($code);
# 	
# 	# Append "exiting" to the error string if it is fatal.
# 	$error .= $anvil->String->get({key => "an_0008"})."\n";
# 	
# 	# Write a copy of the error to the log.
# 	$anvil->Log->entry({file => $THIS_FILE, level => 0, raw => $error});
# 	
# 	# If this is a browser calling us, print the footer so that the loading pinwheel goes away.
# 	if ($ENV{'HTTP_REFERER'})
# 	{
# 		$anvil->Striker->_footer();
# 	}
# 	
# 	# Don't actually die, but do print the error, if fatal errors have been globally disabled (as is done
# 	# in the tests).
# 	if (not $anvil->Alert->no_fatal_errors)
# 	{
# 		if ($ENV{'HTTP_REFERER'})
# 		{
# 			print "<pre>\n";
# 			print "$error\n" if not $anvil->Alert->no_fatal_errors;
# 			print "</pre>\n";
# 		}
# 		else
# 		{
# 			print "$error\n" if not $anvil->Alert->no_fatal_errors;
# 		}
# 		$anvil->data->{sys}{footer_printed} = 1;
# 		$anvil->nice_exit({exit_code => $code});
# 	}
# 	
# 	return ($code);
}

1;
