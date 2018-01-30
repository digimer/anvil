package Anvil::Tools::Words;
# 
# This module contains methods used to handle storage related tasks
# 

use strict;
use warnings;
use Data::Dumper;
use XML::Simple qw(:strict);
use Scalar::Util qw(weaken isweak);

our $VERSION  = "3.0.0";
my $THIS_FILE = "Words.pm";

# Setup for UTF-8 mode.
# use utf8;
# $ENV{'PERL_UNICODE'} = 1;

### Methods;
# clean_spaces
# key
# language
# read
# string

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::Words

Provides all methods related to generating translated strings for users.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();
 
 # Access to methods using '$anvil->Words->X'. 
 # 
 # Example using 'read()';
 my $foo_path = $anvil->Words->read({file => $anvil->data->{path}{words}{'anvil.xml'}});

=head1 METHODS

Methods in this module;

=cut
sub new
{
	my $class = shift;
	my $self  = {
		WORDS	=>	{
			LANGUAGE	=>	"",
		},
	};
	
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

=head2 clean_spaces

This methid takes a string via a 'C<< line >>' parameter and strips leading and trailing spaces, plus compresses multiple spaces into single spaces. It is designed primarily for use by code parsing text coming in from a shell command.

 my $line = $anvil->Words->clean_spaces({ string => $_ });

Parameters;

=head3 string (required)

This sets the string to be cleaned. If it is not passed in, or if the string is empty, then an empty string will be returned without error.

=cut
sub clean_spaces
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Setup default values
	my $string =  defined $parameter->{string} ? $parameter->{string} : "";
	   $string =~ s/^\s+//;
	   $string =~ s/\s+$//;
	   $string =~ s/\s+/ /g;
	
	return($string);
}

=head2 key

NOTE: This is likely not the method you want. This method does no parsing at all. It returns the raw string from the 'words' file. You probably want C<< $anvil->Words->string() >> if you want to inject variables and get a string back ready to display to the user.

This returns a string by its key name. Optionally, a language and/or a source file can be specified. When no file is specified, loaded files will be search in alphabetical order (including path) and the first match is returned. 

If the requested string is not found, 'C<< #!not_found!# >>' is returned.

Example to retrieve 'C<< t_0001 >>';

 my $string = $anvil->Words->key({key => 't_0001'});

Same, but specifying the key from Canadian english;

 my $string = $anvil->Words->key({
 	key      => 't_0001',
 	language => 'en_CA',
 });

Same, but specifying a source file.

 my $string = $anvil->Words->key({
 	key      => 't_0001',
 	language => 'en_CA',
 	file     => 'anvil.xml',
 });

Parameters;

=head3 file (optional)

This is the specific file to read the string from. It should generally not be needed as string keys should not be reused. However, if it happens, this is a way to specify which file's version you want.

The file can be the file name, or a path. The specified file is search for by matching the the passed in string against the end of the file path. For example, 'C<< file => 'AN/anvil.xml' >> will match the file 'c<< /usr/share/perl5/AN/anvil.xml >>'.

=head3 key (required)

This is the key to return the string for.

=head3 language (optional)

This is the ISO code for the language you wish to read. For example, 'en_CA' to get the Canadian English string, or 'jp' for the Japanese string.

When no language is passed, 'C<< Words->language >>' is used. 
 
=cut
sub key
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Setup default values
	my $key      = defined $parameter->{key}      ? $parameter->{key}      : "";
	my $language = defined $parameter->{language} ? $parameter->{language} : $anvil->Words->language;
	my $file     = defined $parameter->{file}     ? $parameter->{file}     : "";
	my $string   = "#!not_found!#";
	my $error    = 0;
	#print $THIS_FILE." ".__LINE__."; [ Debug ] - key: [$key], language: [$language], file: [$file]\n";

	if (not $key)
	{
		#print $THIS_FILE." ".__LINE__."; Anvil::Tools::Words->key()' called without a key name to read.\n";
		$error = 1;
	}
	if (not $language)
	{
		#print $THIS_FILE." ".__LINE__."; Anvil::Tools::Words->key()' called without a language, and 'defaults::languages::output' is not set.\n";
		$error = 2;
	}
	
	if (not $error)
	{
		foreach my $this_file (sort {$a cmp $b} keys %{$anvil->data->{words}})
		{
			#print $THIS_FILE." ".__LINE__."; [ Debug ] - this_file: [$this_file], file: [$file]\n";
			# If they've specified a file and this doesn't match, skip it.
			next if (($file) && ($this_file !~ /$file$/));
			if (exists $anvil->data->{words}{$this_file}{language}{$language}{key}{$key}{content})
			{
				$string = $anvil->data->{words}{$this_file}{language}{$language}{key}{$key}{content};
				#print $THIS_FILE." ".__LINE__."; [ Debug ] - string: [$string]\n";
				last;
			}
		}
	}
	
	#print $THIS_FILE." ".__LINE__."; [ Debug ] - string: [$string]\n";
	return($string);
}

=head2 language

This sets or returns the output language ISO code.

Get the current log language;

 my $language = $anvil->Words->language;
 
Set the output langauge to Japanese;

 $anvil->Words->language({set => "jp"});

=cut
sub language
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $set = defined $parameter->{set} ? $parameter->{set} : "";
	
	if ($set)
	{
		$self->{WORDS}{LANGUAGE} = $set;
	}
	
	if (not $self->{WORDS}{LANGUAGE})
	{
		$self->{WORDS}{LANGUAGE} = $anvil->data->{defaults}{language}{output};
	}
	
	return($self->{WORDS}{LANGUAGE});
}

=head2 read

This reads in a words file containing translated strings used to generated output for the user. 

Example to read 'C<< anvil.xml >>';

 my $words_file = $anvil->data->{path}{words}{'an-words.xml'};
 my $anvil->Words->read({file => $words_file}) or die "Failed to read: [$words_file]. Does the file exist?\n";

Successful read will return '0'. Non-0 is an error;
0 = OK
1 = Invalid file name or path
2 = File not found
3 = File not readable
4 = File found, failed to read for another reason. The error details will be printed.

NOTE: Read works are stored in 'C<< $anvil->data->{words}{<file_name>}{language}{<language>}{string}{content} >>'. Metadata, like what languages are provided, are stored under 'C<< $anvil->data->{words}{<file_name>}{meta}{...} >>'.

Parameters;

=head3 file (required)

This is the file to read.

=cut
sub read
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Setup default values
	my $return_code = 0;
	my $file        = defined $parameter->{file} ? $parameter->{file} : 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { file => $file }});
	
	if (not $file)
	{
		# NOTE: Log the problem, do not translate.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => "[ Error ] - Words->read()' called without a file name to read."});
		$return_code = 1;
	}
	elsif (not -e $file)
	{
		# NOTE: Log the problem, do not translate.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => "[ Error ] - Words->read()' asked to read: [$file] which was not found."});
		$return_code = 2;
	}
	elsif (not -r $file)
	{
		# NOTE: Log the problem, do not translate.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => "[ Error ] - Words->read()' asked to read: [$file] which was not readable by: [".getpwuid($<)."] (uid/euid: [".$<."])."});
		$return_code = 3;
	}
	else
	{
		# Read the file with XML::Simple
		my $xml = XML::Simple->new();
		eval { $anvil->data->{words}{$file} = $xml->XMLin($file, KeyAttr => { language => 'name', key => 'name' }, ForceArray => [ 'language', 'key' ]) };
		if ($@)
		{
			chomp $@;
			my $error =  "[ Error ] - The was a problem reading: [$file]. The error was:\n";
			   $error .= "===========================================================\n";
			   $error .= $@."\n";
			   $error .= "===========================================================\n";
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => $error});
			$return_code = 4;
			die;
		}
		else
		{
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0028", variables => { file => $file }});
		}
	}
	
	return($return_code);
}

=head2 string

This method takes a string key and returns the string in the requested language. If not key is passed, the language key in 'defaults::languages::output' is used. A hash reference containing variables can be provided to inject values into a string.

If the requested string is not found, 'C<< #!not_found!# >>' is returned.

Example to retrieve 'C<< t_0001 >>';

 my $string = $anvil->Words->string({key => 't_0001'});

This time, requesting 'C<< t_0002 >>' and passing in two variables. Note that 'C<< t_0002 >>' in Canadian English is;

 Test Out of order: [#!variable!second!#] replace: [#!variable!first!#].

So to request this string in Canadian English is the two variables inserted, we would call:

 my $string = $anvil->Words->string({	
 	language  => 'en_CA',
 	key       => 't_0002',
 	variables => {
 		first  => "foo",
 		second => "bar",
 	},
 });

This would return;

 Test Out of order: [bar] replace: [foo].

Normally, there should never be a key collision. However, just in case you find yourself needing to request the string from a specific file, you can do the same call with a file specified.

 my $string = $anvil->Words->string({
 	language  => 'en_CA',
 	file      => 'anvil.xml',
 	key       => 't_0002',
 	variables => {
		first  => "foo",
		second => "bar",
 	},
 });

If the passed in key isn't found (at all, or for the given language or file if specified), then 'C<< #!not_found!# >>' will be returned.

Parameters;

=head3 file (optional)

This is the specific file to read the string from. It should generally not be needed as string keys should not be reused. However, if it happens, this is a way to specify which file's version you want.

=head3 key (required)

This is the key to return the string for.

NOTE: This is ignored when 'C<< string >>' is used.

=head3 language (optional)

This is the ISO code for the language you wish to read the string from. For example, 'en_CA' to get the Canadian English string, or 'jp' for the Japanese string.

When no language is passed, 'C<< defaults::languages::output >>' is used. 

=head3 string (optional)

If this is passed, it is treated as a raw string that needs variables inserted. When this is used, the 'C<< key >>' parameter is ignored.

=head3 variables (depends)

If the string being requested has one or more 'C<< #!variable!x!# >>' replacement keys, then you must pass a hash reference containing the keys / value pairs where the key matches the replacement string. 

=cut
sub string
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Setup default values
	my $key       = defined $parameter->{key}       ? $parameter->{key}       : "";
	my $language  = defined $parameter->{language}  ? $parameter->{language}  : $anvil->Words->language;
	my $file      = defined $parameter->{file}      ? $parameter->{file}      : $anvil->data->{path}{words}{'words.xml'};
	my $string    = defined $parameter->{string}    ? $parameter->{string}    : "";
	my $variables = defined $parameter->{variables} ? $parameter->{variables} : "";
	
	# If we weren't passed a raw string, we'll get the string from our ->key() method, then inject any 
	# variables, if needed. This also handles the initial sanity checks. If we get back '#!not_found!#',
	# we'll exit.
	if (not $string)
	{
		$string = $anvil->Words->key({
			key      => $key,
			language => $language,
			file     => $file,
		});
	}
	
	if (($string ne "#!not_found!#") && ($string =~ /#!([^\s]+?)!#/))
	{
		# We've got a string and variables from the caller, so inject them as needed.
		my $loops = 0;
		my $limit = $anvil->data->{defaults}{limits}{string_loops} =~ /^\d+$/ ? $anvil->data->{defaults}{limits}{string_loops} : 1000;
		
		# If the user didn't pass in any variables, then we're in trouble.
		if (($string =~ /#!variable!(.+?)!#/s) && ((not $variables) or (ref($variables) ne "HASH")))
		{
			# Escape the variables before the sending the error 
			while ($string =~ /#!variable!(.+?)!#/s)
			{
				$string =~ s/#!variable!(.*?)!#/!!variable!$1!!/s;
				
				# Die if I've looped too many times.
				$loops++;
				die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			}
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0042", variables => { string => $string }});
			return("#!error!#");
		}
		
		# We set the 'loop' variable to '1' and check it at the end of each pass. This is done 
		# because we might inject a string near the end that adds a replacement key to an 
		# otherwise-processed string and we don't want to miss that.
		my $loop = 1;
		while ($loop)
		{
			# First, look for any '#!...!#' keys that we don't recognize and protect them. We'll
			# restore them once we're out of this loop.
			foreach my $check ($string =~ /#!([^\s]+?)!#/)
			{
				if (($check !~ /^replace/) &&
				    ($check !~ /^data/)    &&
				    ($check !~ /^string/)  &&
				    ($check !~ /^variable/))
				{
					# Simply invert the '#!...!#' to '!#...#!'.
					$string =~ s/#!($check)!#/!#$1#!/g;
				}
				
				# Die if I've looped too many times.
				$loops++;
				die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			}
			
			# Now, look for any '#!string!x!#' embedded strings.
			while ($string =~ /#!string!(.+?)!#/)
			{
				my $key         = $1;
				my $this_string = $anvil->Words->key({
					key      => $key,
					language => $language,
					file     => $file,
				});
				if ($this_string eq "#!not_found!#")
				{
					# The key was bad...
					$string =~ s/#!string!$key!#/!!e[$key]!!/;
				}
				else
				{
					$string =~ s/#!string!$key!#/$this_string/;
				}
				
				# Die if I've looped too many times.
				$loops++;
				die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			}
			
			# Now insert variables in the strings.
			while ($string =~ /#!variable!(.+?)!#/s)
			{
				my $variable = $1;
				
				# Sometimes, #!variable!*!# is used in explaining things to users. So we need
				# to escape it. It will be restored later in '_restore_protected()'.
				if ($variable eq "*")
				{
					$string =~ s/#!variable!\*!#/!#variable!*#!/;
					next;
				}
				if ($variable eq "")
				{
					$string =~ s/#!variable!\*!#/!#variable!#!/;
					next;
				}
				
				if (not defined $variables->{$variable})
				{
					# I can't expect there to always be a defined value in the variables
					# array at any given position so if it is blank qw blank the key.
					$string =~ s/#!variable!$variable!#//;
				}
				else
				{
					my $value = $variables->{$variable};
					chomp $value;
					$string =~ s/#!variable!$variable!#/$value/;
				}
				
				# Die if I've looped too many times.
				$loops++;
				die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			}
			
			# Next, convert '#!data!x!#' to the value in '$anvil->data->{x}'.
			while ($string =~ /#!data!(.+?)!#/)
			{
				my $id = $1;
				if ($id =~ /::/)
				{
					# Multi-dimensional hash.
					my $value = $anvil->_get_hash_reference({ key => $id });
					if (not defined $value)
					{
						$string =~ s/#!data!$id!#/!!a[$id]!!/;
					}
					else
					{
						$string =~ s/#!data!$id!#/$value/;
					}
				}
				else
				{
					# One dimension
					if (not defined $anvil->data->{$id})
					{
						$string =~ s/#!data!$id!#/!!b[$id]!!/;
					}
					else
					{
						my $value  =  $anvil->data->{$id};
						   $string =~ s/#!data!$id!#/$value/;
					}
				}
				
				# Die if I've looped too many times.
				$loops++;
				die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			}
			
			$loops++;
			die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			
			# If there are no replacement keys left, exit the loop.
			if ($string !~ /#!([^\s]+?)!#/)
			{
				$loop = 0;
			}
		}
		
		# Restore any protected keys. Reset the loop counter, too.
		$loops = 0;
		$loop  = 1;
		while ($loop)
		{
			$string =~ s/!#([^\s]+?)#!/#!$1!#/g;
			
			$loops++;
			die "$THIS_FILE ".__LINE__."; Infinite loop detected while processing the string: [".$string."] from the key: [$key] in language: [$language], exiting.\n" if $loops > $limit;
			
			if ($string !~ /!#[^\s]+?#!/)
			{
				$loop = 0;
			}
		}
	}
	
	# In some multi-line strings, the last line will be '\t\t</key>'. We clean this up.
	$string =~ s/\t\t$//;
	
	#print $THIS_FILE." ".__LINE__."; [ Debug ] - string: [$string]\n";
	return($string);
}

# =head3
# 
# Private Functions;
# 
# =cut

#############################################################################################################
# Private functions                                                                                         #
#############################################################################################################

1;
