package RequestTrackerWiki;
use strict;
use warnings FATAL => 'all';

use lib qw(lib);
use LWP::UserAgent;
use JSON;
use Data::Dumper;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

# ==== wiki stuff
#     https://wiki.mobiusconsortium.org/w/index.php?title=Special:Pages&sfr=w
#
#     This Special:Pages list all the pages in the wiki. We can get the page contents via the title + the url like so
#     wget https://wiki.mobiusconsortium.org/wiki/20241216-OpenRS-Admin-Stop-Borrowing-Lending
#
#
#     How can I get all of these title programmatically?
#         https://wiki.mobiusconsortium.org/w/api.php?action=query&list=allpages&aplimit=max&format=json
#
#
#     https://wiki.mobiusconsortium.org/w/index.php?title=MOBIUS_Maintenance_of_Shared_Book_Records_Checklist&action=raw
#     https://wiki.mobiusconsortium.org/w/index.php?curid=210&action=raw

sub fetchWikiPage
{
    my $self = shift;

    my $pageID = shift;
    # my $url = "https://wiki.mobiusconsortium.org/w/api.php?action=query&titles=$page&prop=revisions&rvprop=content&format=json";
    my $url = "https://wiki.mobiusconsortium.org/w/index.php?curid=$pageID&action=raw";

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($url);

    if ($response->is_success)
    {
        # my $result = decode_json($response->content);
        # return $result;
        return $response->content;
    }
    else
    {
        die "API request failed: " . $response->status_line . "\n" . $response->content;
    }
}

sub fetchAllWikiPages
{
    my $self = shift;
    my $url = "https://wiki.mobiusconsortium.org/w/api.php?action=query&list=allpages&aplimit=max&format=json";
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($url);

    if ($response->is_success)
    {
        my $result = decode_json($response->content);
        return $self->fetchCleanWikiPages($result->{query}->{allpages});
    }
    else
    {
        die "API request failed: " . $response->status_line . "\n" . $response->content;
    }
}

# removes the 'ns' field from the wiki page data
sub fetchCleanWikiPages
{
    my $self = shift;
    my $pages = shift;

    my @cleaned_pages;
    foreach my $page (@$pages)
    {
        my %clean_page;
        foreach my $key (keys %$page)
        {
            # Skip the 'ns' field
            next if $key eq 'ns';
            $clean_page{$key} = $page->{$key};
        }
        push @cleaned_pages, \%clean_page;
    }

    return \@cleaned_pages;
}

sub fetchAllWikiPagesWithContent
{
    my $self = shift;

    my $json = $self->fetchAllWikiPages();
    my @wiki_pages;

    for my $page (@$json)
    {
        $page->{content} = $self->fetchWikiPage($page->{pageid});

        push @wiki_pages, $page;
    }

    return \@wiki_pages;

}

1;
