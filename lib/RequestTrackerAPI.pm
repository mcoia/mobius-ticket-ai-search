package RequestTrackerAPI;

use strict;
use warnings FATAL => 'all';
use Data::Dumper;
use LWP::UserAgent;
use URI;
use URI::Escape;

sub new
{
    my $class = shift;

    # Check for required parameters $dbname, $host, $username, $password;
    die "Missing required parameters. Usage: RequestTrackerAPI->new(url, user, pass)"
        unless @_ == 3;

    my $self = {
        'domain' => shift,
        'user'   => shift,
        'pass'   => shift
    };
    bless $self, $class;
    return $self;
}

sub executeAPIRequest
{
    my $self = shift;
    my $endpoint = shift;
    my $content = "";

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    $ua->agent($main::conf->{user_agent});

    # my $uri = $self->{domain} . $endpoint;
    my $uri = URI->new($self->{domain} . $endpoint);

    my $response = $ua->post(
        $uri,
        [ 'user' => $self->{user}, 'pass' => $self->{pass} ],
        'Content-Type' => 'application/x-www-form-urlencoded'
    );

    $content = $response->{_content} if ($response->is_success);

    return $content;
}

# /REST/1.0/search/ticket?query=Queue='fooQueue'
sub getTicketsByQueue
{
    my $self = shift;
    my $queue = shift;
    my $moduleName = shift || "";
    my $startDate = shift || "2024-05-22";

    # Example response:
    # RT/4.4.4 200 Ok
    #
    # 191908: Inventory (enhancement)
    # 193977: WWU Locate requests
    # 194633: FOLIO Bulk Edit - modify material type Enhancement Request
    # 195273: Folio enhancement request: Due date behavior
    # 196699: Folio enhancement request - Bulk Edit app
    # 197208: FOLIO: A few enhancement requests from STLCC

    # my $endpoint = "/REST/1.0/search/ticket?query=Queue+%3D+%27$queue%27";

    my $encoded_queue = uri_escape($queue);
    my $encoded_module = uri_escape($moduleName);

    my $endpoint = "/REST/1.0/search/ticket?query=Queue+%3D+%27$encoded_queue%27+AND+LastUpdated+%3E+%27$startDate%27";

    # Add module to the query if it's provided
    $endpoint = $endpoint . "+AND+CF.%7BModule%7D+LIKE+%27$encoded_module%27" if ($moduleName ne "");

    my @tickets = ();

    my $content = $self->executeAPIRequest($endpoint);

    # iterate of the $content line by line removing empty lines that don't start with a number
    my @lines = split /\n/, $content;

    # loop over lines looking for 'RT/4.4.4 200 Ok'
    for (@lines)
    {
        my $line = $_;
        next if $line =~ m/^RT\/\d+\.\d+\.\d+ 200 Ok$/;

        # 191506: WWU: Connexion to FOLIO push
        # 191520: KGS: Connexion
        # 191644: MSSU OCLC Connexion Client

        # we are a ticket line, so build our hash entry
        if ($line =~ m/\d+:/)
        {
            my ($ticket) = $line =~ /(\d+):/;
            push @tickets, { 'ticket_id' => $ticket };
        }
    }

    # [ { ticket_id, subject_line }, {...} ]
    # Returns an array of hashes containing ticket_id and subject_line
    return \@tickets;
}

# /REST/1.0/ticket/<ticket-id>/show
sub getTicketMetaDataById
{
    my $self = shift;
    my $ticket_id = shift;
    my $endpoint = "/REST/1.0/ticket/$ticket_id/show";
    my $content = $self->executeAPIRequest($endpoint);
    my @lines = split /\n/, $content;
    my %ticketMetaData;

    # Define which fields are timestamps
    my %timestamp_fields = map {$_ => 1} qw(
        created
        started
        due
        resolved
        told
        last_updated
    );

    for (@lines)
    {
        my $line = $_;
        next if ($line !~ m/:/);
        my $key = "";
        my $value = "";

        if ($line =~ m/CF\./)
        {
            # Handle custom fields
            $key = "requesting_entity" if ($line =~ m/CF\.\{Requesting Entity\}/);
            $key = "severity_level" if ($line =~ m/CF\.\{Severity Level\}/);
            $key = "emergency_change" if ($line =~ m/CF\.\{Emergency Change\}/);
            $key = "ebsco_ticket_number" if ($line =~ m/CF\.\{EBSCO ticket number\}/);
            $key = "module" if ($line =~ m/CF\.\{Module\}/);

            if ($line =~ /:\s*(.*)/)
            {
                $value = $1;
            }

            $ticketMetaData{$key} = $value if $key;
            next;
        }

        # Handle regular fields
        $key = $1 if ($line =~ /^(\w+):/);
        $value = $1 if ($line =~ /:\s*(.*)/);

        # Convert keys to match database column names
        if ($key eq 'id' && $value =~ m/ticket\/(\d+)/)
        {
            $key = 'ticket_id';
            $value = $1;
        }
        else
        {
            # Convert other keys to snake_case
            $key = lc($key); # Convert to lowercase
            $key = 'initial_priority' if $key eq 'initialpriority';
            $key = 'final_priority' if $key eq 'finalpriority';
            $key = 'admin_cc' if $key eq 'admincc';
            $key = 'last_updated' if $key eq 'lastupdated';
            $key = 'time_estimated' if $key eq 'timeestimated';
            $key = 'time_worked' if $key eq 'timeworked';
            $key = 'time_left' if $key eq 'timeleft';
        }

        # Set value to undef (NULL) if it's a timestamp field and value is 'Not set'
        if ($timestamp_fields{$key} && ($value eq 'Not set' || $value eq ''))
        {
            $value = undef;
        }

        $ticketMetaData{$key} = $value if $key;
    }

    return \%ticketMetaData;
}

# /REST/1.0/ticket/<ticket-id>/history
sub getTicketHistoryById
{
    my $self = shift;
    my $ticket_id = shift;

    my $endpoint = "/REST/1.0/ticket/$ticket_id/history";
    my $content = $self->executeAPIRequest($endpoint);
    my @lines = split /\n/, $content;
    my @ticketHistory = ();

    # loop over lines looking for 'RT/4.4.4 200 Ok'
    for (@lines)
    {
        my $line = $_;

        next if ($line !~ m/:/);

        # 191506: WWU: Connexion to FOLIO push
        if ($line =~ m/^\d+:/)
        {

            # ticket_id   int,
            # history_id  int,
            # subject     text,
            my ($history_id, $subject) = $line =~ /(\d+):\s*(.*)/;
            $history_id = $history_id + 0; # convert to int, lol
            push @ticketHistory, {
                'history_id' => $history_id,
                'ticket_id'  => $ticket_id,
                # 'subject'    => $subject # the subject is in the content and this is more of a mapping table.
                # I think request tracker has a bad design because they stash this subject everywhere! If someone updates the subject
                # I bet you $1 that they have to update each table that contains the subject instead of having it in 1 place.
                # We don't play those games! It goes in the content table.
            };
        }

    }

    return \@ticketHistory;

}

# /REST/1.0/ticket/<ticket-id>/history/id/<history-id>
sub getTicketContentByHistoryId
{
    my $self = shift;
    my $ticket_id = shift;
    my $history_id = shift;

    my $endpoint = "/REST/1.0/ticket/$ticket_id/history/id/$history_id";
    my $data = $self->executeAPIRequest($endpoint);

    my $ticket_content = {
        'ticket_id'  => $ticket_id,
        'history_id' => $history_id
    };

    # Create mapping for the fields we want
    my %field_map = (
        'Description' => 'description',
        'Content'     => 'content',
        'Creator'     => 'creator',
        'Created'     => 'created'
    );

    # Split the content at boundaries where a new field starts
    my @sections = split /\n(?=\w+:)/, $data;

    foreach my $section (@sections)
    {
        if ($section =~ /^(\w+):\s*(.*)$/s)
        {
            my $key = $1;
            my $value = $2;

            if (exists $field_map{$key})
            {
                $value =~ s/^\s+|\s+$//g if defined $value;
                $ticket_content->{$field_map{$key}} = $value // '';
            }
        }
    }

    return $ticket_content;
}

1;