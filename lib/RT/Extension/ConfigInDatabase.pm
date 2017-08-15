package RT::Extension::ConfigInDatabase;
use strict;
use warnings;
use RT::DatabaseSetting;
use RT::DatabaseSettings;
use Storable;

our $VERSION = '0.01';

RT->AddStyleSheets("config-in-database.css");

for (qw/DatabaseAdmin DatabaseExtraDSN DatabaseHost DatabaseName
        DatabasePassword DatabasePort DatabaseRTHost DatabaseType
        DatabaseUser

        WebBaseURL WebDomain WebPath WebPort WebURL

        Organization rtname Plugins MailPlugins

        RecordBaseClass WebSessionClass DevelMode DisallowExecuteCode

        ExternalAuthPriority ExternalInfoPriority
        ExternalSettings/) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Immutable} = 1;
}

# special case due to being autovivified from other options
$RT::Config::META{ExternalAuth}{Immutable} = 1
    if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;

for (qw/AllowUserAutocompleteForUnprivileged AlwaysDownloadAttachments
        AmbiguousDayInFuture AmbiguousDayInPast ApprovalRejectionNotes
        ArticleOnTicketCreate AutocompleteOwnersForSearch
        CanonicalizeRedirectURLs CanonicalizeURLsInFeeds
        ChartsTimezonesInDB CheckMoreMSMailHeaders DateDayBeforeMonth
        DisableGD DisableGraphViz
        DontSearchFileAttachments DropLongAttachments
        EditCustomFieldsSingleColumn EnableReminders
        ExternalStorageDirectLink ForceApprovalsView ForwardFromUser
        Framebusting HideArticleSearchOnReplyCreate
        HideResolveActionsWithDependencies
        HideTimeFieldsFromUnprivilegedUsers LoopsToRTOwner
        MessageBoxIncludeSignature MessageBoxIncludeSignatureOnComment
        OnlySearchActiveTicketsInSimpleSearch ParseNewMessageForTicketCcs
        PreferDateTimeFormatNatural PreviewScripMessages RecordOutgoingEmail
        RestrictLoginReferrer RestrictReferrer SearchResultsAutoRedirect
        ShowBccHeader ShowMoreAboutPrivilegedUsers ShowRTPortal
        ShowRemoteImages ShowTransactionImages StoreLoops StrictLinkACL
        SuppressInlineTextFiles TruncateLongAttachments
        TrustHTMLAttachments UseFriendlyFromLine UseFriendlyToLine
        UseOriginatorHeader UseSQLForACLChecks UseTransactionBatch
        ValidateUserEmailAddresses WebFallbackToRTLogin
        WebFlushDbCacheEveryRequest WebHttpOnlyCookies WebRemoteUserAuth
        WebRemoteUserAutocreate WebRemoteUserContinuous WebRemoteUserGecos
        WebSecureCookies WikiImplicitLinks

        HideOneTimeSuggestions LinkArticlesOnInclude
        MessageBoxUseSystemContextMenu
        SelfServiceCorrespondenceOnly ShowSearchResultCount

        DevelMode DisallowExecuteCode ExternalAuth
    /) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/Boolean';
    $RT::Config::META{$_}{WidgetArguments} = {};
}

for (qw/AttachmentListCount AutoLogoff BcryptCost DefaultSummaryRows
        ExternalStorageCutoffSize LogoImageHeight LogoImageWidth LogoutRefresh
        MaxAttachmentSize MaxFulltextAttachmentSize MessageBoxRichTextHeight
        MinimumPasswordLength MoreAboutRequestorGroupsLimit TicketsItemMapSize
        DatabasePort
       /) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/Integer';
    $RT::Config::META{$_}{WidgetArguments} = {};
}

for (qw/CommentAddress CorrespondAddress DashboardAddress DashboardSubject
        DefaultErrorMailPrecedence DefaultMailPrecedence
        DefaultSearchResultOrderBy EmailOutputEncoding FriendlyFromLineFormat
        FriendlyToLineFormat HTMLFormatter LogDir LogToFileNamed LogoAltText
        LogoLinkURL LogoURL MailCommand OwnerEmail
        RedistributeAutoGeneratedMessages SendmailArguments
        SendmailBounceArguments SendmailPath SetOutgoingMailFrom Timezone
        WebImagesURL DatabaseAdmin DatabaseHost DatabaseName
        DatabaseRTHost DatabaseType DatabaseUser Organization RecordBaseClass
        WebBaseURL WebDomain WebPath WebPort WebSessionClass WebURL
        rtname
       /) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/String';
    $RT::Config::META{$_}{WidgetArguments} = {};
}

for (qw/AssetSearchFormat AssetSummaryFormat AssetSummaryRelatedTicketsFormat
        DefaultSearchResultFormat DefaultSelfServiceSearchResultFormat
        MoreAboutRequestorExtraInfo MoreAboutRequestorTicketListFormat
        UserSearchResultFormat UserSummaryExtraInfo UserSummaryTicketListFormat
       /) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/MultilineString';
    $RT::Config::META{$_}{WidgetArguments} = {};
}

for (qw/LogToSyslog LogToSTDERR LogToFile LogStackTraces StatementLog/) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/Select';
    $RT::Config::META{$_}{WidgetArguments}{Values} = [qw(
        debug info notice warning error critical alert emergency
    )];
}

for (qw/DefaultSearchResultOrder/) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/Select';
    $RT::Config::META{$_}{WidgetArguments}{Values} = [qw(
        ASC DESC
    )];
}
# special case due to being only for PostLoadCheck
$RT::Config::META{RestrictReferrerLogin}{Invisible} = 1;

my $config_cache_time;
my %original_setting_from_files;

__PACKAGE__->LoadConfigFromDatabase();

sub LoadConfigFromDatabase {
    my $class = shift;

    $config_cache_time = time;
    RT->Logger->info("Loading config from database");

    my $settings = RT::DatabaseSettings->new(RT->SystemUser);
    $settings->UnLimit;

    my %seen;

    while (my $setting = $settings->Next) {
        my $name = $setting->Name;
        my ($value, $error) = $setting->DecodedContent;
        next if $error;

        use Data::Dumper;
        local $Data::Dumper::Terse = 1;
        RT->Logger->debug("from database: Set('$name', ".Dumper($value).");");

        if (!exists $original_setting_from_files{$name}) {
            $original_setting_from_files{$name} = [
                scalar(RT->Config->Get($name)),
                Storable::dclone(scalar(RT->Config->Meta($name))),
            ];
        }

        $seen{$name}++;

        # are we inadvertantly overriding RT_SiteConfig.pm?
        my $meta = RT->Config->Meta($name);
        if ($meta->{'Source'}) {
            my %source = %{ $meta->{'Source'} };
            if ($source{'SiteConfig'} && $source{'File'} ne 'database') {
                RT->Logger->warning("Change of config option '$name' at $source{File} line $source{Line} has been overridden by the config setting from the database. Please remove it from $source{File} or from the database to avoid confusion.");
            }
        }

        my $type = $meta->{Type} || 'SCALAR';

        # hashes combine, but we don't want that behavior because the previous
        # config settings will shadow any change that the database config makes
        if ($type eq 'HASH') {
            RT->Config->Set($name, ());
        }

        my $val = $type eq 'ARRAY' ? $value
                : $type eq 'HASH'  ? [ %$value ]
                                   : [ $value ];

        RT->Config->SetFromConfig(
            Option     => \$name,
            Value      => $val,
            Package    => 'N/A',
            File       => 'database',
            Line       => 'N/A',
            SiteConfig => 1,
        );
    }

    # anything that wasn't loaded from the database but has been set in
    # %original_setting_from_files must have been disabled from the database,
    # so we want to restore the original setting
    for my $name (keys %original_setting_from_files) {
        next if $seen{$name};

        my ($value, $meta) = @{ $original_setting_from_files{$name} };
        my $type = $meta->{Type} || 'SCALAR';

        if ($type eq 'ARRAY') {
            RT->Config->Set($name, @$value);
        }
        elsif ($type eq 'HASH') {
            RT->Config->Set($name, %$value);
        }
        else {
            RT->Config->Set($name, $value);
        }

        %{ RT->Config->Meta($name) } = %$meta;
    }
}

sub ConfigCacheNeedsUpdate {
    my $self = shift;
    my $time = shift;

    if ($time) {
        return RT->System->SetAttribute(Name => 'ConfigCacheNeedsUpdate', Content => $time);
    } else {
        my $cache = RT->System->FirstAttribute('ConfigCacheNeedsUpdate');
        return (defined $cache ? $cache->Content : 0 );
    }
}

my $in_config_change_txn = 0;
sub BeginConfigChanges {
    $in_config_change_txn = $in_config_change_txn + 1;
}

sub EndConfigChanges {
    $in_config_change_txn = $in_config_change_txn - 1;
    if (!$in_config_change_txn) {
        shift->ApplyConfigChangeToAllServerProcesses();
    }
}

sub ApplyConfigChangeToAllServerProcesses {
    my $class = shift;

    return if $in_config_change_txn;

    # first apply locally
    $class->LoadConfigFromDatabase();

    # then notify other servers
    $class->ConfigCacheNeedsUpdate($config_cache_time);
}

do {
    require RT::Interface::Web;
    no warnings 'redefine';

    my $orig_HandleRequest = RT::Interface::Web->can('HandleRequest');
    *RT::Interface::Web::HandleRequest = sub {
        if ($in_config_change_txn) {
            RT->Logger->error("It appears that there were unbalanced calls to BeginConfigChanges with EndConfigChanges; this indicates a software fault");
            $in_config_change_txn = 0;
        }

        my $needs_update = __PACKAGE__->ConfigCacheNeedsUpdate;
        if ($needs_update > $config_cache_time) {
            __PACKAGE__->LoadConfigFromDatabase();
            $config_cache_time = $needs_update;
        }
        $orig_HandleRequest->(@_);
    };
};

=head1 NAME

RT-Extension-ConfigInDatabase - update RT config via admin UI

=head1 INSTALLATION

=over

=item perl Makefile.PL

=item make

=item make install

This step may require root permissions.

=item Edit your /opt/rt4/etc/RT_SiteConfig.pm

Add this line:

    Plugin( "RT::Extension::ConfigInDatabase" );

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=back

=head1 AUTHOR

Best Practical Solutions, LLC E<lt>modules@bestpractical.comE<gt>

=head1 BUGS

All bugs should be reported via email to

    L<bug-RT-Extension-ConfigInDatabase@rt.cpan.org|mailto:bug-RT-Extension-ConfigInDatabase@rt.cpan.org>

or via the web at

    L<rt.cpan.org|http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-ConfigInDatabase>.

=head1 COPYRIGHT

This extension is Copyright (C) 2017 Best Practical Solutions, LLC.

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
