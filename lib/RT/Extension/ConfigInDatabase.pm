package RT::Extension::ConfigInDatabase;
use strict;
use warnings;
use RT::DatabaseSetting;
use RT::DatabaseSettings;

our $VERSION = '0.01';

RT->AddStyleSheets("config-in-database.css");

for (qw/DatabaseAdmin DatabaseExtraDSN DatabaseHost DatabaseName
        DatabasePassword DatabasePort DatabaseRTHost DatabaseType
        DatabaseUser

        WebBaseURL WebDomain WebPath WebPort WebURL

        Organization rtname Plugins MailPlugins

        RecordBaseClass WebSessionClass DevelMode

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
        DisableGD DisableGraphViz DisallowExecuteCode
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
        SelfServiceCorrespondenceOnly ShowSearchResultCount/) {
    next if !$RT::Config::META{$_};

    $RT::Config::META{$_}{Widget} = '/Widgets/Form/Boolean';
    $RT::Config::META{$_}{WidgetArguments} = {};
}

__PACKAGE__->LoadConfigFromDatabase();

sub LoadConfigFromDatabase {
    my $class = shift;

    my $settings = RT::DatabaseSettings->new(RT->SystemUser);
    $settings->UnLimit;

    while (my $setting = $settings->Next) {
        my $name = $setting->Name;
        my $value = $setting->Content;

        use Data::Dumper;
        local $Data::Dumper::Terse = 1;
        RT->Logger->debug("from database: Set('$name', ".Dumper($value).");");

        # are we inadvertantly overriding RT_SiteConfig.pm?
        my $meta = RT->Config->Meta($name);
        my %source = %{ $meta->{'Source'} };
        if ($source{'SiteConfig'} && $source{'File'} ne 'database') {
            RT->Logger->warning("Change of config option '$name' at $source{File} line $source{Line} has been overridden by the config setting from the database. Please remove it from $source{File} or from the database to avoid confusion.");
        }

        RT->Config->SetFromConfig(
            Option     => \$name,
            Value      => [$value],
            Package    => 'N/A',
            File       => 'database',
            Line       => 'N/A',
            SiteConfig => 1,
        );
    }
}

sub ApplyConfigChangeToAllServerProcesses {
    my $class = shift;

    # first apply locally
    $class->LoadConfigFromDatabase();

    # then notify other servers
    # XXX
}

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
