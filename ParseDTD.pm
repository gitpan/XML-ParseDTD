=head1 NAME 

XML::ParseDTD - parses a XML DTD and provides methods to access the
information stored in the DTD.

=cut

######################################################################

package XML::ParseDTD;
require 5.004;

# Copyright (c) 2003, Moritz Sinn. This module is free software;
# you can redistribute it and/or modify it under the terms of the
# GNU GENERAL PUBLIC LICENSE, see COPYING for more information.

use strict;
use vars qw($VERSION);
$VERSION = '0.1';

######################################################################

=head1 DEPENDENCIES

=head2 Perl Version

	5.004

=head2 Standard Modules

        Carp 1.01

=head2 Nonstandard Modules

        LWP::UserAgent 0.01
        IPC::SharedCache 1.3

=cut

######################################################################

use Switch;
use Carp;
use LWP::UserAgent;
use IPC::SharedCache;

######################################################################

=head1 SYNOPSIS

use XML::ParseDTD;

$dtd = XML::ParseDTD->new($dtd);

$bool = $dtd->child_allowed($tag, $childtag);

$bool = $dtd->child_list_allowed($tag, @childtags);

$bool = $dtd->attr_allowed($tag, $attribute);

$bool = $dtd->attr_list_allowed($tag, @attributes);

$bool = $dtd->is_empty($tag);

$bool = $dtd->is_defined($tag);

$bool = $dtd->is_fixed($tag, $attribute);

$bool = $dtd->attr_value_allowed($tag, $attribute, $value);

$bool = $dtd->attr_list_value_allowed($tag, \%attribute_value);

@tags = $dtd->get_document_tags();

$regexp = $dtd->get_child_regexp($tag);

@attributes = $dtd->get_attributes($tag);

@req_attributes = $dtd->get_req_attributes($tag);

$value = $dtd->get_allowed_attr_values($tag, $attribute);

$default_value = $dtd->get_attr_def_value($tag, $attribute);

$dtd->clear_cache();

$errormessage = $dtd->errstr;

$errornumber = $dtd->err;

=head1 DESCRIPTION

ParseDTD.pm is a Perl 5 object class which provides methods to access
the information stored in a XML DTD.

This module basically tells you which tags are known by the dtd, which
child tags a certain tag might have, which tags are defined as a empty
tag, which attributes a certain tag might have, which values are
allowed for a certain attribute, which attributes are required, which
attributes are fixed, which attributes have which default value
... well i would say it tells you all except the entity definitions (they're on the ToDo list) that is defined in the dtd (at
least all that i know of, but i'm not so much into that topic, so
please make me aware if i missed something). All this information can
be accessed in 2 diffrent ways: 1. you can simply get it 2. you can
pass certain data and the module then tells you whether thats ok or
not.

This package uses IPC::SharedCache to cache every parsed DTD, so 
next time the data structure representing the dtd can be just taken out of
memory. Thus the dtd is not refetched and not parsed again which saves
quite some time and work.

Everytime the constructor is called it first checks whether the given
dtd is already in memory, if so it compares the I<last modified> date
to the date stored in memory and then decides whether it should
refetch it or not. If the dtd lays on the local filesystem this
operation doesn't produce any reasonable overhead, but if the dtd is
fetched out of the internet it might make sense to not check the
I<last modified> header every time. You can configure how often it
should be checked, by default it is checked averaged every third
time. But since most dtds don't change it is mostly save to not check
it at all.

Internally the parsed DTD data is simply stored in 6 hash
structures. Because of this and because of the caching the module
should be very fast.

=head1 USING XML::ParseDTD

=head2 The Constructor

=head3 new ($dtd_url, [ %conf ])

This method is the constructor. The first argument must be the path to
a xml dtd, it should be a valid URL using the file or http
protocol. Here are some examples:

=over

=item 

http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd

=item

/home/moritz/xhtml1-strict.dtd

=item

file://home/moritz/xhtml1-strict.dtd

=back

The configuration hash can be used to influence the modules
behaviour. So far only one configuration option is known:

=over

=item

B<checklm> - configures how often the I<Last-Modified> header should
be checked if the http protocol is used. The Default is I<3> that
means that averaged it is checked every third time (dtd is refetched
and reparsed if it was modified meanwhile). Setting it to 1 or 0 will
force the module to always check the I<Last-Modified> header, setting
it to -1 will force it to never check the header (which is recommend
if performance is important and its more or less sure that the dtd
will not be changed).

=back

=cut

######################################################################

my $checklm = 3;
my $ipc_key = 'XML::ParseDTD';

sub new {
  my ($class, $dtd, %conf) = @_;
  $checklm = $conf{checklm} if(defined($conf{checklm}));
  my %cache;
  tie %cache, 'IPC::SharedCache', ipc_key => $ipc_key, load_callback => \&_load, validate_callback => \&_validate;
  $_ = $cache{$dtd};
  my $self = bless($_, ref($class) || $class);
  return $self;
}

######################################################################

=head2 Check Methods

=head3 child_allowed ($tag, $childtag)

Checks whether the given tag can contain the given childtag.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub child_allowed {
  my($self,$tag,$child) = @_;
  $self->_set_errstr(1,$tag) and return 0 unless($self->{'Element'}->{$tag});
  return 1 if (eval("'" . $self->{'Element'}->{$tag} . "'" . "=~ m/($child,)/"));
  $self->_set_errstr(4,$child,$tag);
  return 0;
}

######################################################################

=head3 child_list_allowed ($tag, @childtags)

Checks whether its ok if the given tag contains the given childtags in
the given order.  This means that the method will return ails if a
certain tag is not allowed, a required tag is not given or the order
is not allowed.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub child_list_allowed {
  my($self,$tag,@childs) = @_;
  $self->_set_errstr(1,$tag) and return 0 unless($self->{'Element'}->{$tag});
  local $_ = join(',', @childs);
  $_ .= ',';
  return 1 if(eval('/' . $self->{'Element'}->{$tag} . '/'));
  chop();
  $self->_set_errstr(5, $_, $tag);
  return 0;
}

######################################################################

=head3 attr_allowed ($tag, $attribute)

Checks whether the given attribute is allowed for the given tag.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub attr_allowed {
  my($self,$tag,$attr) = @_;
  $self->_set_errstr(1,$tag) and return 0 unless($self->{'Element'}->{$tag});
  $self->_set_errstr(2,$tag) and return 0 unless(defined($self->{'Attr'}->{$tag}));
  return 1 if($self->{'Attr'}->{$tag}->{$attr});
  $self->_set_errstr(3,$tag,$attr);
  return 0;
}

######################################################################

=head3 attr_list_allowed ($tag, @attributes)

Checks whether its ok if the given tag has set given attributes.  This
means that the method will return fails if a certain attribute is not
allowed or a required attribute is not given.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub attr_list_allowed {
  my($self,$tag,@attrs) = @_;
  $self->_set_errstr(1,$tag) and return 0 unless($self->{'Element'}->{$tag});
  $self->_set_errstr(2,$tag) and return 0 unless(defined($self->{'Attr'}->{$tag}));
  my %req;
  %req = %{$self->{'ReqAtt'}->{$tag}} if(defined($self->{'ReqAtt'}->{$tag}));
  foreach $_ (@attrs) {
    $self->_set_errstr(3,$_,$tag) and return 0 unless(defined($self->{'Attr'}->{$tag}->{$_}));
    delete $req{$_} if(defined($req{$_}));
  }
  return 1 unless(scalar keys(%req));
  $self->_set_errstr(6,join(',', keys(%req)),$tag);
  return 0;
}

######################################################################

=head3 is_empty ($tag)

Checks whether the given tag is a empty tag, that means whether it
can't contain any elements or data.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub is_empty {
  my($self,$tag) = @_;
  return 1 if($self->{'Empty'}->{$tag});
  $self->_set_errstr(8, $tag);
  return 0;
}

######################################################################

=head3 is_defined ($tag)

Checks whether the given tag is defined in the dtd, that means whether
it is allowed in the document.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub is_defined {
  my($self,$tag) = @_;
  return 1 if(defined($self->{Element}->{$tag}));
  $self->_set_errstr(1, $tag);
  return 0;
}

######################################################################

=head3 is_fixed ($tag, $attribute)

Checks whether the given attribute for the given tag is a fixed
attribute, that means if its value is predefined by the dtd.

If so, you can use C<get_allowed_attr_values> to get the predefined
value.

Returns 1 (true) or 0 (false)

=cut

######################################################################

sub is_fixed {
  my($self,$tag,$attr) = @_;
  return 0 unless($self->attr_allowed($tag,$attr));
  return 1 if($self->{FixAtt}->{$tag}->{$attr});
  $self->_set_errstr(9, $attr, $tag);
  return 0;
}

######################################################################

=head3 attr_value_allowed ($tag, $attribute, $value)

Checks whether the given attribute for the given tag might be set to
the given value.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub attr_value_allowed {
  my($self,$tag,$attr,$value) = @_;
  return 0 unless($self->attr_allowed($tag,$attr));
  for(ref($self->{'Attr'}->{$tag}->{$attr})) {
    m/HASH/ && do {
      $self->_set_errstr(7,$value,$attr,$tag) && return 0 unless($self->{'Attr'}->{$tag}->{$attr}->{$value});
      last;
    };
    m/^$/ && do {
      $self->_set_errstr(7,$value,$attr,$tag) && return 0 unless($self->{'Attr'}->{$tag}->{$attr} == $value);
      last;
    };
    m/ARRAY/ && do {
      my $rex=$self->{Attr}->{$tag}->{$attr}->[1];
      $self->_set_errstr(7,$value,$attr,$tag) && return 0 unless($value =~ m/$rex/);
      last;
    };
  }
  return 1;
}

######################################################################

=head3 attr_list_value_allowed ($tag, \%attribute_value)

Calls C<attr_list_allowed> for the attribute names, if everything is
fine it calls C<attr_value_allowed> for each value.

Returns 1 (true) or 0 (false).

=cut

######################################################################

sub attr_list_value_allowed {
  my($self,$tag,$attr_value) = @_;
  croak "2. argument must be HASHREF" unless(ref($attr_value) eq 'HASH');
  return 0 unless($self->attr_list_allowed($tag,keys(%$attr_value)));
  foreach $_ (keys(%$attr_value)) {
    return 0 unless($self->attr_value_allowed($tag,$_,$attr_value->{$_}));
  }
  return 1;
}

######################################################################

=head2 Get Methods

=head3 get_document_tags

Returns a list of all tags which are defined in the dtd, that means
which are allowed in the document.

=cut

######################################################################

sub get_document_tags {
  my $self = shift;
  return keys(%{$self->{Element}});
}

######################################################################

=head3 get_child_regexp ($tag)

Returns the regular expression, which defines which combinations of
child elements are valid for the given tag, as a string.

=cut

######################################################################

sub get_child_regexp {
  my($self,$tag) = @_;
  return undef unless($self->is_defined($tag));
  return $self->{'Element'}->{$tag};
}

######################################################################

=head3 get_attributes ($tag)

Returns a list of all attributes which are allowed for the given tag.

=cut

######################################################################

sub get_attributes {
  my($self,$tag) = @_;
  return undef unless($self->is_defined($tag));
  return keys(%{$self->{Attr}->{$tag}}) if(defined($self->{Attr}->{$tag}));
  return ();
}

######################################################################

=head3 get_req_attributes ($tag)

Returns a list of all required attributes for the given tag.

=cut

######################################################################

sub get_req_attributes {
  my($self,$tag) = @_;
  return undef unless($self->is_defined($tag));
  return keys(%{$self->{ReqAtt}->{$tag}}) if(defined($self->{ReqAtt}->{$tag}));
  return ();
}

######################################################################

=head3 get_allowed_attr_values ($tag,$attribute)

Returns the allowed values for the given attribute for the given tag.

If only one certain string is allowed to be set as value, this string
is returned.  If the value must be one string out of a list of
strings, a reference to this list is returned.  If the value must be
of a certain datatype such as PCDATA, ID or NMTOKEN, a reference to a
hash with only one element is returned. The key is the name of the
datatype and the value is a regular expression string which describes
the datatype.

undef is returned if nothing is defined as attribute value, that
normally means that the attribute is not known for the given tag, but
you can call C<errstr> to get more information.

=cut

######################################################################

sub get_allowed_attr_values {
  my($self,$tag,$attr) = @_;

  return undef unless($self->is_defined($tag));
  return undef unless($self->attr_allowed($tag,$attr));

  if(defined($self->{Attr}->{$tag}->{$attr})) {
    if(ref($self->{Attr}->{$tag}->{$attr}) eq 'HASH') {
      return [keys(%{$self->{Attr}->{$tag}->{$attr}})];
    }
    elsif(ref($self->{Attr}->{$tag}->{$attr}) eq 'ARRAY') {
      return {$self->{Attr}->{$tag}->{$attr}->[0] => $self->{Attr}->{$tag}->{$attr}->[1]};
    }
    else {
      return $self->{Attr}->{$tag}->{$attr};
    }
  }
  #this should never be the case since $self->{Attr}->{$tag}->{$attr} should always be defined if the attribute is allowed
  return undef;
}

######################################################################

=head3 get_attr_def_value ($tag,$attribute)

Returns the default value defined for the given attribute of the given
tag. In most cases no default value is defined, that means that undef
is returned. But undef is also returned if the tag does not exist or
if the attribute is not allowed for the given tag. To get more
information why undef was returned, you should call C<errstr>.

=cut

######################################################################

sub get_attr_def_value {
  my($self,$tag,$attr) = @_;

  return undef unless($self->is_defined($tag));
  return undef unless($self->attr_allowed($tag,$attr));

  return $self->{DefAtt}->{$tag}->{$attr} if(defined($self->{DefAtt}->{$tag}->{$attr}));
  $self->_set_errstr(10,$attr,$tag);
  return undef;
}

######################################################################

=head2 Other Methods

=head3 clear_cache ()

Clears the cache, that means that all dtds will be refetched and
reparsed.

=cut

######################################################################

sub clear_cache {
  IPC::SharedCache::remove $ipc_key;
}

######################################################################

=head3 errstr ()

Returns the message of the last occured error.

=cut

######################################################################

sub errstr {
  my($self) = @_;
  return $self->{errstr};
}

######################################################################

=head3 err ()

Returns the number of the last occured error.

=cut

######################################################################

sub err {
  my($self) = @_;
  return $self->{err};
}


######################################################################
# INTERNAL MEHTODS                                                   #
######################################################################

sub _set_errstr {
  my($self, $err) = (shift, shift);
  $self->{errstr} = _get_errstr($err,@_);
  $self->{err} = $err;
}

sub _get_errstr {
  my $err = shift;
  my $msg;
  for ($err) {
    $msg = /^1$/  && sprintf("Unkown tag '%s'", @_)
        || /^2$/  && sprintf("'%s' has no attributes", @_)
	|| /^3$/  && sprintf("Attribute '%s' not allowed for '%s'", @_)
	|| /^4$/  && sprintf("'%s' is not allowed in '%s'", @_)
        || /^5$/  && sprintf("Child list '%s' not allowed for '%s'", @_)
        || /^6$/  && sprintf('Required Attribute(s) "%s" for "%s" not defined', @_)
	|| /^7$/  && sprintf('Value "%s" not allowed for attribute "%s" of "%s"', @_)
        || /^8$/  && sprintf('"%s" is not a empty tag', @_)
        || /^9$/  && sprintf('Attribute "%s" for "%s" is not fixed', @_)
        || /^10$/ && sprintf('No default value defined for attribute "%s" of "%s"', @_)
	|| '';
  }
  return $msg;
}

#sub _check_id {
#  $_ = shift;
#  return 0 if(m/^[A-Za-z_]{1}[A-Za-z0-9_:.-]*$/ && ! m/^(xml|XML)/);
#  return 'must be of type ID which means it must match ^[A-Za-z]{1}[A-Za-z0-9_:.-]*$ and mustn\'t begin with xml or XML';
#}

#sub _check_idrefs {
#  $_ = shift;
#  return 0 if(m/^[A-Za-z_]{1}[A-Za-z0-9_:. -]*$/ && ! m/(^| )(xml|XML)/);
#  return 'must be of type IDREFS which means it must match ^[A-Za-z]{1}[A-Za-z0-9_:. -]*$ and mustn\'t begin with xml or XML';
#}

#sub _check_cdata {
#  return 0 ;
#}

#sub _pcdata {
#  return 0 ;
#}

#sub _check_nmtoken {
#  return 0 if(shift =~ m/^[A-Za-z0-9_:.-]{1}\S*$/);
#  return 'must be of type NMTOKEN which means it must match ^[A-Za-z0-9_:.-]{1}\S*$';
#}

#this method fetches and parses the dtd
sub _load {
  my $dtd = shift;
  my %pdtd = (
	      'Element' => {},
	      'Empty' => {},
	      'Attr' => {},
	      'ReqAtt' => {},
	      'FixAtt' => {},
	      'DefAtt' => {},
	     );
  my $DTD;
  if($dtd =~ m/^(?!file)([A-za-z]+):\/\//i) {
    my $ua = LWP::UserAgent->new(timeout => 30);
    local $_;
    $_ = $ua->get($dtd);
    $DTD = $_->content;
    $pdtd{lmod} = $_->last_modified;
  }
  else {
    $dtd =~ s/^file:\/\///;
    open DTD, "<$dtd" or die "Cannot open file $dtd : $!\n";
    {
      local $/;
      $DTD = <DTD>;
    }
    close DTD;
    $pdtd{lmod} = (stat($dtd))[9];
  }

  $DTD =~ s/<!--.*?-->//gs;
  
  my %IntEntity;
  while($DTD =~ s/<!ENTITY\s*%\s*(\S+)\s*[A-Z]*\s*(?:"([^"]*?)"\s*)+>//os) {
    $IntEntity{$1} = $2;
  }
  
  my $entity;
  foreach $_ (keys(%IntEntity)) {
    #$IntEntity{$_} =~ s/%(\S+);/$IntEntity{$1}/gs;
    while($IntEntity{$_} =~ s/%(\S+);/$IntEntity{$1}/s) {}
  }
  
  #$DTD =~ s/%(\S+);/$IntEntity{$1}/gs;
  while($DTD =~ s/%(\S+);/$IntEntity{$1}/s) {}

  while($DTD =~ s/<!ELEMENT\s*(\S+)\s*(?:(\([^<>]*\)(\*|\+)?)|(EMPTY))\s*>//s) {
    if(!$4) {
      $_ = $1;
      $pdtd{'Element'}->{$_} = $2;
      $pdtd{'Element'}->{$_} =~ s/\s*//gs;
      $pdtd{'Element'}->{$_} =~ s/([a-zA-Z0-9#]+)(?!(,|[a-zA-Z0-9#]))/$1,/gs;
      $pdtd{'Element'}->{$_} =~ s/([a-zA-Z0-9#]+,)/($1)/gs;
      $pdtd{'Element'}->{$_} =~ s/([^a-zA-Z0-9#]{1}),/$1/gs;
    }
    else {
      $pdtd{'Element'}->{$1} = 1;
      $pdtd{'Empty'}->{$1} = 1;
    }
  }
  
  my $elem;
  while($DTD =~ s/<!ATTLIST\s*(\S+)\s*([^<>]*)>//s) {
    $elem = $1;
    $pdtd{'Attr'}->{$elem} = {};
    $_ = $2;
    my ($attr,$type,$some,$default);
    while(s/\s*(\S+)\s*((?:\([^\(\)]+\))|(?:[^\(\) \n]+))\s*(\S+)?\s*((?:"|')\S+(?:'|"))?\s*//s) {
      ($attr,$type,$some,$default) = ($1,$2,$3,$4);
      for($type) {
	#/^ID(REF)?$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = \&XML::ParseDTD::_check_id; last; };
	/^ID(REF)?$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = ['ID', '^[A-Za-z_]{1}[A-Za-z0-9_:.-]*$']; last; };
	#/^IDREFS$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = \&XML::ParseDTD::_check_idrefs; last; };
	/^IDREFS$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = ['IDREFS', '^[A-Za-z_]{1}[A-Za-z0-9_:. -]*$']; last; };
	#/^CDATA$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = \&XML::ParseDTD::_check_cdata; last; };
	/^CDATA$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = ['CDATA', '.*']; last; };
	#/^PCDATA$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = \&XML::ParseDTD::_check_pcdata; last; };
	/^PCDATA$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = ['PCDATA', '.*']; last; };
	#/^NMTOKEN$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = \&XML::ParseDTD::_check_nmtoken; last; };
	/^NMTOKEN$/ && do { $pdtd{'Attr'}->{$elem}->{$attr} = ['NMTOKEN', '^[A-Za-z0-9_:.-]{1}\S*$']; last; };
	/^\((.*)\)$/s && do {
	  $_ = $1;
	  s/\s//gs;
	  my @allowed = split(/\|/s, $_);
	  if(@allowed > 1) {
	    $pdtd{'Attr'}->{$elem}->{$attr} = {};
	    foreach my $value (@allowed) {
	      $pdtd{'Attr'}->{$elem}->{$attr}->{$value} = 1;
	    }
	  }
	  else {
	    $pdtd{'Attr'}->{$elem}->{$attr} = $allowed[0];
	  }
	  last;
	};
      }
      for($some) {
	/#IMPLIED/ && do { last; };
	/#REQUIRED/ && do { $pdtd{'ReqAtt'}->{$elem}->{$attr} = 1; last; };
	/#FIXED/ && do { $pdtd{'FixAtt'}->{$elem}->{$attr} = 1; last; };
	($pdtd{'DefAtt'}->{$elem}->{$attr} = $some) =~ s/("|')//g if($some);
      }
      ($pdtd{'DefAtt'}->{$elem}->{$attr} = $default)  =~ s/("|')//g if($default);
    }
  }
  return \%pdtd;
}

#this method proves whether the dtd is already cached and if so if it should be refetched (and reparsed)
sub _validate {
  my ($dtd,$rec) = @_;
  my $lmod;
  if($dtd =~ m/^(?!file)([A-za-z]+):\/\//i) {
    $lmod = ($checklm < 0 || int(rand($checklm))) ? $rec->{lmod} : LWP::UserAgent->new(timeout => 1)->head($dtd)->last_modified;
  }
  else {
    $lmod = (stat($dtd))[9];
  }
  return ($lmod == $rec->{lmod}) ? 1 : 0;
}

######################################################################
return 1;
__END__

=head1 BUGS

Send bug reports to: moritz@freesources.org

Thanks!

=head1 AUTHOR

(c) 2003, Moritz Sinn. This module is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License (see http://www.gnu.org/licenses/gpl.txt) as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

    This module is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

I am always interested in knowing how my work helps others, so if you put this module to use in any of your own code then please send me the URL. If you make modifications to the module because it doesn't work the way you need, please send me a copy so that I can roll desirable changes into the main release.

Address comments, suggestions, and bug reports to moritz@freesources.org. 

=cut
