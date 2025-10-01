#!/usr/bin/perl
use strict;
use warnings;
no warnings 'utf8';

use lib qw(lib);

use Getopt::Long;
use Data::Dumper;
use JSON;
use MOBIUS::Utils;
use MOBIUS::Loghandler;
use RequestTrackerAPI;
use DAO;
use RequestTrackerService;
use RequestTrackerElastic;
use RequestTrackerWiki;
use AI;
use AIFactory;
use Time::HiRes qw(time);

# Our global variables
our ($service, $log, $conf);

initConf();
initLogger();
main();

sub main
{

    $log->addLogLine("Starting Request Tracker Service");

    my $dao = DAO->new($conf->{dbname}, $conf->{host} || 'localhost', $conf->{username}, $conf->{password}, $conf->{schema});
    my $api = RequestTrackerAPI->new($conf->{domain}, $conf->{user}, $conf->{pass});
    my $elasticSearch = RequestTrackerElastic->new($conf->{es_url}, $conf->{es_user}, $conf->{es_pass});
    my $ai = AIFactory::createGemini2FlashAI();
    my $textEmbedding = AIFactory::createNomicEmbeddingModel();
    my $wiki = RequestTrackerWiki->new();

    # print "indices: " . $elasticSearch->listIndices();
    # print "Health Check: " . Dumper($elasticSearch->healthCheck());

    $service = RequestTrackerService->new($dao, $api, $ai, $elasticSearch, $textEmbedding, $wiki);
    # $service->processTicketQueues();
    # $service->buildAISummaries();

    # # WORKS!!!!
    print "Ticket Summary Elastic Search\n";
    $service->saveTicketSummaryElasticSearch();
    #
    # # WORKS!!!!
    # print "Ticket Embeddings Elastic Search\n";
    # $service->processWikiPages();
    #
    # print "Ticket Embeddings Elastic Search\n";
    # $service->processFolioDocs();
    #
    # # WORKS!!!!
    # print "Ticket Embeddings Elastic Search\n";
    # $service->saveTicketEmbeddingsElasticSearch();

    # my $endpoint = "/REST/1.0/search/ticket?query=Queue+%3D+%27$queue%27";

}

sub initConf
{
    my $utils = MOBIUS::Utils->new();
    $conf = $utils->readConfFile("rt.conf");
    exit if ($conf eq "false");
}

sub initLogger
{
    $log = Loghandler->new($conf->{log_file});
    $log->truncFile("");
}
