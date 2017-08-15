use strict;
use warnings;
use 5.10.1;

package RT::DatabaseSetting;
use base 'RT::Record';

use Storable ();
use MIME::Base64;
use JSON ();

=head1 NAME

RT::DatabaseSetting - Represents a config setting

=cut

=head1 METHODS

=head2 Create PARAMHASH

Create takes a hash of values and creates a row in the database.  Available
keys are:

=over 4

=item Name

Must be unique.

=item Content

If you provide a reference, we will automatically serialize the data structure
using L<Storable>. Otherwise any string is passed through as-is.

=item ContentType

Currently handles C<storable> or C<application/json>.

=back

Returns a tuple of (status, msg) on failure and (id, msg) on success.
Also automatically propagates this config change to all server processes.

=cut

sub Create {
    my $self = shift;
    my %args = (
        Name => '',
        Content => '',
        ContentType => '',
        @_,
    );

    return (0, $self->loc("Permission Denied"))
        unless $self->CurrentUserHasRight('SuperUser');

    unless ( $args{'Name'} ) {
        return ( 0, $self->loc("Must specify 'Name' attribute") );
    }

    my ( $id, $msg ) = $self->ValidateName( $args{'Name'} );
    return ( 0, $msg ) unless $id;

    my $meta = RT->Config->Meta($args{'Name'});
    if ($meta->{Immutable}) {
        return ( 0, $self->loc("You cannot update [_1] using database config; you must edit your site config", $args{'Name'}) );
    }

    if (ref ($args{'Content'}) ) {
        ($args{'Content'}, my $error) = $self->_SerializeContent($args{'Content'}, $args{'Name'});
        if ($error) {
            return (0, $error);
        }
        $args{'ContentType'} = 'storable';
    }

    my $old_value = RT->Config->Get($args{Name});
    unless (defined($old_value) && length($old_value)) {
        $old_value = $self->loc('(no value)');
    }

    ( $id, $msg ) = $self->SUPER::Create(
        map { $_ => $args{$_} } grep {exists $args{$_}}
            qw(Name Content ContentType),
    );
    unless ($id) {
        return (0, $self->loc("Setting [_1] to [_2] failed: [_3]", $args{Name}, $args{Content}, $msg));
    }

    RT::Extension::ConfigInDatabase->ApplyConfigChangeToAllServerProcesses;

    my ($content, $error) = $self->Content;
    unless (defined($content) && length($content)) {
        $content = $self->loc('(no value)');
    }

    if (!ref($content) && !ref($old_value)) {
        RT->Logger->info($self->CurrentUser->Name . " changed " . $self->Name . " from " . $old_value . " to " . $content);
        return ($id, $self->loc("[_1] changed from [_2] to [_3]", $self->Name, $old_value, $content));
    }
    else {
        RT->Logger->info($self->CurrentUser->Name . " changed " . $self->Name);
        return ($id, $self->loc("[_1] changed", $self->Name));
    }
}

=head2 CurrentUserCanSee

Returns true if the current user can see the database setting

=cut

sub CurrentUserCanSee {
    my $self = shift;

    return $self->CurrentUserHasRight('SuperUser');
}

=head2 Load

Load a setting from the database. Takes a single argument. If the
argument is numerical, load by the column 'id'. Otherwise, load by the
"Name" column.

=cut

sub Load {
    my $self = shift;
    my $identifier = shift || return undef;

    if ( $identifier !~ /\D/ ) {
        return $self->SUPER::LoadById( $identifier );
    } else {
        return $self->LoadByCol( "Name", $identifier );
    }
}

=head2 SetName

Not permitted

=cut

sub SetName {
    my $self = shift;
    return (0, $self->loc("Permission Denied"));
}

=head2 ValidateName

Returns either (0, "failure reason") or 1 depending on whether the given
name is valid.

=cut

sub ValidateName {
    my $self = shift;
    my $name = shift;

    return ( 0, $self->loc('empty name') ) unless defined $name && length $name;

    my $TempSetting = RT::DatabaseSetting->new( RT->SystemUser );
    $TempSetting->Load($name);

    if ( $TempSetting->id && ( !$self->id || $TempSetting->id != $self->id ) ) {
        return ( 0, $self->loc('Name in use') );
    }
    else {
        return 1;
    }
}

=head2 Delete

Checks ACL, and on success propagates this config change to all server
processes.

=cut

sub Delete {
    my $self = shift;
    return (0, $self->loc("Permission Denied")) unless $self->CurrentUserCanSee;
    my ($ok, $msg) = $self->SUPER::Delete(@_);
    return ($ok, $msg) if !$ok;
    RT::Extension::ConfigInDatabase->ApplyConfigChangeToAllServerProcesses;
    RT->Logger->info($self->CurrentUser->Name . " removed database setting for " . $self->Name);
    return ($ok, $self->loc("Database setting removed."));
}

=head2 DecodedContent

Returns a pair of this setting's content and any error.

=cut

sub DecodedContent {
    my $self = shift;

    # Here we call _Value to run the ACL check.
    my $content = $self->_Value('Content');

    my $type = $self->__Value('ContentType') || '';

    if ($type eq 'storable') {
        return $self->_DeserializeContent($content);
    }
    elsif ($type eq 'application/json') {
        return $self->_DeJSONContent($content);
    }

    return ($content, "");
}

=head2 SetContent

=cut

sub SetContent {
    my $self         = shift;
    my $value        = shift;
    my $content_type = shift || '';

    return (0, $self->loc("Permission Denied")) unless $self->CurrentUserCanSee;

    my ($old_value, $error) = $self->Content;
    unless (defined($old_value) && length($old_value)) {
        $old_value = $self->loc('(no value)');
    }

    if (ref $value) {
        ($value, my $error) = $self->_SerializeContent($value);
        if ($error) {
            return (0, $error);
        }
        $content_type = 'storable';
    }

    $RT::Handle->BeginTransaction;

    my ($ok, $msg) = $self->_Set( Field => 'Content', Value => $value );
    if (!$ok) {
        $RT::Handle->Rollback;
        return ($ok, $self->loc("Unable to update [_1]: [_2]", $self->Name, $msg));
    }

    if ($self->ContentType ne $content_type) {
        ($ok, $msg) = $self->_Set( Field => 'ContentType', Value => $content_type );
        if (!$ok) {
            $RT::Handle->Rollback;
            return ($ok, $self->loc("Unable to update [_1]: [_2]", $self->Name, $msg));
        }
    }

    $RT::Handle->Commit;
    RT::Extension::ConfigInDatabase->ApplyConfigChangeToAllServerProcesses;

    unless (defined($value) && length($value)) {
        $value = $self->loc('(no value)');
    }

    if (!ref($value) && !ref($old_value)) {
        RT->Logger->info($self->CurrentUser->Name . " changed " . $self->Name . " from " . $old_value . " to " . $value);
        return ($ok, $self->loc("[_1] changed from [_2] to [_3]", $self->Name, $old_value, $value));
    } else {
        RT->Logger->info($self->CurrentUser->Name . " changed " . $self->Name);
        return ($ok, $self->loc("[_1] changed", $self->Name));
    }
}

=head1 PRIVATE METHODS

Documented for internal use only, do not call these from outside
RT::DatabaseSetting itself.

=head2 _Set

Checks if the current user has I<SuperUser> before calling
C<SUPER::_Set>, and then propagates this config change to all server processes.

=cut

sub _Set {
    my $self = shift;
    my %args = (
        Field => undef,
        Value => undef,
        @_
    );

    return (0, $self->loc("Permission Denied"))
        unless $self->CurrentUserCanSee;

    my ($ok, $msg) = $self->SUPER::_Set(@_);
    RT::Extension::ConfigInDatabase->ApplyConfigChangeToAllServerProcesses;
    return ($ok, $msg);
}

=head2 _Value

Checks L</CurrentUserCanSee> before calling C<SUPER::_Value>.

=cut

sub _Value {
    my $self = shift;
    return unless $self->CurrentUserCanSee;
    return $self->SUPER::_Value(@_);
}

sub _SerializeContent {
    my $self = shift;
    my $content = shift;
    my $name = shift || $self->Name;
    my $frozen = eval { encode_base64(Storable::nfreeze($content)) };

    if (my $error = $@) {
        $RT::Logger->error("Storable serialization of database setting $name failed: $error");
        return (undef, $self->loc("Storable serialization of database setting [_1] failed: [_2]", $name, $error));
    }

    return $frozen;
}

sub _DeserializeContent {
    my $self = shift;
    my $content = shift;

    my $thawed = eval { Storable::thaw(decode_base64($content)) };
    if (my $error = $@) {
        $RT::Logger->error("Storable deserialization of database setting " . $self->Name . " failed: $error");
        return (undef, $self->loc("Storable deserialization of database setting [_1] failed: [_2]", $self->Name, $error));
    }

    return $thawed;
}

sub _DeJSONContent {
    my $self = shift;
    my $content = shift;

    my $thawed = eval { JSON::from_json($content) };
    if (my $error = $@) {
        $RT::Logger->error("JSON deserialization of database setting " . $self->Name . " failed: $error");
        return (undef, $self->loc("JSON deserialization of database setting [_1] failed: [_2]", $self->Name, $error));
    }

    return $thawed;
}

sub Table { "RTxDatabaseSettings" }

sub _CoreAccessible {
    {
        id            => { read => 1, type => 'int(11)',        default => '' },
        Name          => { read => 1, sql_type => 12, length => 255,  is_blob => 0,  is_numeric => 0,  type => 'varchar(255)', default => ''},
        Content       => { read => 1, write => 1, sql_type => -4, length => 0,  is_blob => 1,  is_numeric => 0,  type => 'blob', default => ''},
        ContentType   => { read => 1, write => 1, sql_type => 12, length => 16,  is_blob => 0,  is_numeric => 0,  type => 'varchar(16)', default => ''},
        Disabled      => { read => 1, write => 1, sql_type => 5, length => 6,  is_blob => 0,  is_numeric => 1,  type => 'smallint(6)', default => '0'},
        Creator       => { read => 1, type => 'int(11)',        default => '0', auto => 1 },
        Created       => { read => 1, type => 'datetime',       default => '',  auto => 1 },
        LastUpdatedBy => { read => 1, type => 'int(11)',        default => '0', auto => 1 },
        LastUpdated   => { read => 1, type => 'datetime',       default => '',  auto => 1 },
    }
}

1;

