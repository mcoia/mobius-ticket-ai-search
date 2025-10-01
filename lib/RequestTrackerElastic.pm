package RequestTrackerElastic;
use strict;
use warnings FATAL => 'all';
use LWP::UserAgent;
use JSON;
use MIME::Base64;

sub new
{
    my ($class, $url, $username, $password) = @_;
    my $ua = LWP::UserAgent->new(
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => 0x00
        }
    );

    my $self = {
        url      => $url,
        username => $username,
        password => $password,
        ua       => $ua,
        index    => 'tickets'
    };
    bless $self, $class;
    return $self;
}

sub _makeRequest
{
    my ($self, $method, $endpoint, $data, $skip_index, $override_url) = @_;

    # Use override_url if provided, otherwise construct URL normally
    my $url = $override_url || ($skip_index ?
        "$self->{url}$endpoint" :
        "$self->{url}/$self->{index}$endpoint");

    my $request = HTTP::Request->new(
        $method => $url,
        [
            'Content-Type'  => 'application/json',
            'Authorization' => 'Basic ' . encode_base64("$self->{username}:$self->{password}")
        ]
    );

    $request->content(encode_json($data)) if $data;
    my $response = $self->{ua}->request($request);

    unless ($response->is_success)
    {
        print "URL: $url\n";
        print "Method: $method\n";
        print "Data: " . encode_json($data) . "\n" if $data;
        print "Response: " . $response->content . "\n";
        die "Request failed: " . $response->status_line;
    }
    return decode_json($response->content);
}

sub healthCheck
{
    my ($self) = @_;
    return $self->_makeRequest('GET', '/_cluster/health', undef, 1);
}

sub indexExists
{
    my $self = shift;
    my $indexName = shift;

    # Use the default index if none provided
    $indexName ||= $self->{index};

    # Use HEAD request to check if index exists
    my $url = "$self->{url}/$indexName";
    my $request = HTTP::Request->new(
        'HEAD' => $url,
        [
            'Authorization' => 'Basic ' . encode_base64("$self->{username}:$self->{password}")
        ]
    );

    my $response = $self->{ua}->request($request);

    # Return 1 if the index exists (status code 200), 0 otherwise
    return $response->code == 200 ? 1 : 0;
}

sub createIndex
{
    my ($self, $indexName, $mappings) = @_;

    # Require mappings parameter
    die "Mappings parameter is required" unless $mappings;

    # Use default index name if not provided
    $indexName ||= $self->{index};

    # Override default index for this request
    my $originalIndex = $self->{index};
    $self->{index} = $indexName;

    # Create the index with mappings
    my $result = $self->_makeRequest('PUT', '', { mappings => $mappings });

    # Restore original index
    $self->{index} = $originalIndex;

    return $result;
}

sub getDocCount
{
    my ($self, $index) = @_;
    $index ||= $self->{index};
    my $result = $self->_makeRequest('GET', '/_count', undef, 1, "$self->{url}/$index/_count");
    return $result->{count};
}

sub importData
{
    my ($self, $index, $results) = @_;

    die "No results provided for import" unless $results && ref($results) eq 'ARRAY';
    return 1 if scalar(@$results) == 0;

    # Set a reasonable chunk size to avoid "Request Entity Too Large" errors
    my $chunk_size = 1000;
    my $total_records = scalar(@$results);
    my $processed = 0;
    my $success_count = 0;

    print "Importing " . $total_records . " documents in chunks of " . $chunk_size . "...\n";

    # Process the data in chunks
    while ($processed < $total_records)
    {
        my $end = $processed + $chunk_size - 1;
        $end = $total_records - 1 if $end >= $total_records;

        my @chunk = @$results[$processed .. $end];
        my $chunk_records = scalar(@chunk);

        # Build the bulk import data for this chunk
        my $bulk_data = '';
        foreach my $record (@chunk)
        {
            # Decode JSON strings if needed
            if ($record->{keywords} && !ref($record->{keywords}))
            {
                eval {$record->{keywords} = decode_json($record->{keywords})};
            }
            if ($record->{key_points_discussed} && !ref($record->{key_points_discussed}))
            {
                eval {$record->{key_points_discussed} = decode_json($record->{key_points_discussed})};
            }

            # Create the action line
            my $action = {
                index => {
                    _index => $index,
                    _id    => $record->{ticket_id}
                }
            };

            $bulk_data .= encode_json($action) . "\n";
            $bulk_data .= encode_json($record) . "\n";
        }

        # Send the bulk request for this chunk
        my $url = "$self->{url}/_bulk?refresh=true";
        my $request = HTTP::Request->new(
            'POST' => $url,
            [
                'Content-Type'  => 'application/x-ndjson',
                'Authorization' => 'Basic ' . encode_base64("$self->{username}:$self->{password}")
            ]
        );

        $request->content($bulk_data);
        my $response = $self->{ua}->request($request);

        unless ($response->is_success)
        {
            print "URL: $url\n";
            print "Method: POST\n";
            print "Response: " . $response->content . "\n";
            die "Bulk import failed at chunk $processed-$end: " . $response->status_line;
        }

        my $result = decode_json($response->content);

        # Check for errors
        if ($result->{errors})
        {
            my @errors = grep {$_->{index}->{error}} @{$result->{items}};
            if (@errors)
            {
                print "Chunk $processed-$end had errors: " . encode_json(\@errors);
                # Continue instead of die, so we can process other chunks
            }
        }

        $success_count += $chunk_records - ($result->{errors} ? scalar(grep {$_->{index}->{error}} @{$result->{items}}) : 0);
        $processed += $chunk_records;

        printf("Progress: %d/%d (%.1f%%)\n", $processed, $total_records, ($processed / $total_records) * 100);
    }

    # Force index refresh
    $self->_makeRequest('POST', '/_refresh', undef, 1);

    print "Successfully imported $success_count of $total_records documents\n";
    return { success => 1, total => $total_records, imported => $success_count };
}

sub listIndices
{
    my ($self) = @_;
    my $url = $self->{url} . '/_cat/indices?v';
    my $request = HTTP::Request->new(
        'GET' => $url,
        [
            'Content-Type'  => 'application/json',
            'Authorization' => 'Basic ' . encode_base64("$self->{username}:$self->{password}")
        ]
    );
    my $response = $self->{ua}->request($request);
    unless ($response->is_success)
    {
        print "URL: $url\n";
        print "Response: " . $response->content . "\n";
        die "Request failed: " . $response->status_line;
    }
    return $response->content;
}

sub sqlSearch
{
    my $self = shift;
    my $sql_query = shift;
    return $self->_makeRequest('POST', '/_sql', {
        query => $sql_query
    }, 1);
}

sub search
{
    my ($self, $query) = @_;
    return $self->_makeRequest('GET', '/_search', $query);
}

sub getById
{
    my ($self, $id) = @_;
    return $self->_makeRequest('GET', "/_doc/$id");
}

sub deleteById
{
    my ($self, $id) = @_;
    return $self->_makeRequest('DELETE', "/_doc/$id");
}

sub deleteIndex
{
    my ($self, $index_name) = @_;

    # If no index name provided, use default
    $index_name ||= $self->{index};

    # Delete the index
    return $self->_makeRequest('DELETE', '', undef, 1, "$self->{url}/$index_name");
}

sub updateById
{
    my ($self, $id, $doc) = @_;
    return $self->_makeRequest('POST', "/_doc/$id/_update", {
        doc => $doc
    });
}

sub updateMapping
{
    my ($self, $mapping) = @_;
    return $self->_makeRequest('PUT', '/_mapping', {
        properties => $mapping
    });
}

sub searchByEmbedding
{
    my ($self, $index, $embedding, $field, $k, $additional_query) = @_;

    # Validate required parameters
    die "Index name is required" unless $index;
    die "Embedding vector is required" unless $embedding;
    die "Field name is required" unless $field;

    # Set optional parameter defaults
    $k ||= 10; # Number of results to return

    # Ensure embedding is in the correct format (array reference)
    my $embedding_array;
    if (ref($embedding) eq 'ARRAY')
    {
        $embedding_array = $embedding;
    }
    else
    {
        # If it's a string, try to parse it
        if ($embedding =~ /^\[.*\]$/)
        {
            # Remove brackets and split by commas
            $embedding =~ s/^\[|\]$//g;
            $embedding_array = [ split(/,\s*/, $embedding) ];

            # Convert strings to numbers
            $embedding_array = [ map {0 + $_} @$embedding_array ];
        }
        else
        {
            die "Embedding must be an array reference or a string in the format '[0.1,0.2,...]'";
        }
    }

    # Build the query for vector similarity search
    my $query = {
        size  => $k,
        query => {
            script_score => {
                query  => $additional_query || { match_all => {} },
                script => {
                    source => "cosineSimilarity(params.query_vector, doc['$field']) + 1.0",
                    params => {
                        query_vector => $embedding_array
                    }
                }
            }
        }
    };

    # Use the search method to perform the query
    return $self->_makeRequest('GET', '/_search', $query, 1, "$self->{url}/$index/_search");
}

1;
