package RequestTrackerService;
use strict;
use warnings FATAL => 'all';
use lib qw(lib);
use Data::Dumper;
use AI::Gemini;
use AI::4o_mini;
use RequestTrackerElastic;
use JSON;
use Parallel::ForkManager;
use Encode;

use File::Find;
use File::Spec;
use Cwd 'abs_path';
use File::Basename;

sub new
{
    my $class = shift;
    my $self = {
        'dao'           => shift,
        'api'           => shift,
        'ai'            => shift,
        'elasticSearch' => shift,
        'textEmbedding' => shift,
        'wiki'          => shift,
    };
    bless $self, $class;
    return $self;
}

sub processTicketQueues
{
    my $self = shift;

    my $time = localtime;
    $main::log->addLogLine("**************************************************");
    print "*" x 80 . "\n";
    $main::log->addLogLine("Starting Request Tracker Service - $time");
    print "Starting Request Tracker Service - $time\n";
    print "*" x 80 . "\n";
    $main::log->addLogLine("**************************************************");

    my $queues = $self->getRequestTrackerQueues();
    my $modules = $self->getRequestTrackerModules();

    $main::log->addLogLine("Found queues: " . join(", ", @$queues) . "");
    print "Found queues: " . join(", ", @$queues) . "\n\n";
    $main::log->addLogLine("Found modules: " . join(", ", @$modules) . "");
    print "Found modules: " . join(", ", @$modules) . "\n\n";

    for my $queue (@$queues)
    {
        # If this is the General queue, process by module only
        if ($queue eq "General")
        {
            $main::log->addLogLine("Processing General queue by modules only");
            print "Processing General queue by modules only\n";

            for my $module (@$modules)
            {
                $main::log->addLogLine("--------------------------------------------------");
                print "--------------------------------------------------\n";
                $main::log->addLogLine("Fetching tickets from General queue with module: $module");
                print "Fetching tickets from General queue with module: $module\n";

                my $start_date = $main::conf->{search_start_date};
                my $module_tickets = $self->{api}->getTicketsByQueue($queue, $module, $start_date);
                $self->saveNewTicketIds($module_tickets);

                # process each module ticket
                my $module_ticket_count = 0;
                foreach my $ticket (@$module_tickets)
                {
                    $module_ticket_count++;
                    $main::log->addLogLine("Processing module ticket $module_ticket_count of " .
                        scalar(@$module_tickets) . " in queue $queue, module $module");
                    $self->processTicket($ticket);
                }

                $main::log->addLogLine("Completed processing all tickets in queue $queue, module $module");
                $main::log->addLogLine("--------------------------------------------------");
            }

            $main::log->addLogLine("Completed processing General queue by modules");
            print "Completed processing General queue by modules\n";
        }
        else
        {
            # Process non-General queues as before
            $main::log->addLogLine("Fetching tickets from queue: $queue");
            print "Fetching tickets from queue: $queue\n";

            my $start_date = $main::conf->{search_start_date};
            my $tickets = $self->{api}->getTicketsByQueue($queue, "", $start_date);
            $self->saveNewTicketIds($tickets);

            # process each ticket
            my $ticket_count = 0;
            foreach my $ticket (@$tickets)
            {
                $ticket_count++;
                $main::log->addLogLine("Processing ticket $ticket_count of " . scalar(@$tickets) . " in queue $queue");
                $self->processTicket($ticket);
            }
            $main::log->addLogLine("Completed processing all tickets in queue: $queue");
        }

    }

    # At this point all the tickets have been processed and saved to the database
    $time = localtime;
    $main::log->addLogLine("**************************************************");
    $main::log->addLogLine("Finished Request Tracker Service - $time");
    $main::log->addLogLine("**************************************************");

    # Now we build the ticket embeddings.
    $main::log->addLogLine("Building ticket embeddings...");
    $self->buildTicketEmbeddings();
    $main::log->addLogLine("Ticket embeddings built successfully");

    return $self;
}

# Helper functions for min and max values
sub min
{
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

sub max
{
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub processTicket
{
    my $self = shift;
    my $ticket = shift;

    $main::log->addLogLine("Processing ticket: " . $ticket->{ticket_id} . "");

    # Get the meta data for the ticket and save it
    my $ticket_meta = $self->{api}->getTicketMetaDataById($ticket->{ticket_id});
    $self->saveTicketMetaData($ticket_meta);

    # Get the ticket history id's and save them too!
    my $ticket_history_ids = $self->{api}->getTicketHistoryById($ticket->{ticket_id});
    $self->saveTicketHistory($ticket, $ticket_history_ids);

    # We only want to process the ones that we haven't already processed
    my $filtered_content_ids = $self->filterTicketHistory($ticket->{ticket_id}, $ticket_history_ids);
    my @ticket_content_array = ();
    foreach my $row (@$filtered_content_ids)
    {
        $main::log->addLogLine("Processing ticket content: " . $ticket->{ticket_id} . " - " . $row->{history_id} . "");
        my $ticket_content = $self->{api}->getTicketContentByHistoryId($ticket->{ticket_id}, $row->{history_id});
        push @ticket_content_array, $ticket_content;
    }

    # now we bulk insert the ticket content
    if (@ticket_content_array)
    {
        $main::log->addLogLine("Bulk inserting " . scalar(@ticket_content_array) . " content records for ticket: " . $ticket->{ticket_id} . "");
        $self->{dao}->batchInsert('ticket_content', \@ticket_content_array);
    }
    else
    {$main::log->addLogLine("No new content to insert for ticket: " . $ticket->{ticket_id} . "");}

    $main::log->addLogLine("Completed processing ticket: " . $ticket->{ticket_id} . "");
    $main::log->addLogLine("========================================================");
}

sub filterTicketHistory
{
    my $self = shift;
    my $ticketId = shift;
    my $ticket_history_ids = shift;

    my $schema = $self->{dao}->{schema};
    $self->{dao}->connect();

    # Query existing history IDs for this ticket
    my $existing_history = $self->{dao}->query("SELECT history_id FROM $schema.ticket_content WHERE ticket_id = ?", $ticketId);

    # Create a hash of existing history IDs for lookup
    my %existing_history_ids = map {$_->{history_id} => 1} @$existing_history;

    # Filter out history IDs that already exist
    my @filtered_history_ids = grep {
        !exists $existing_history_ids{$_->{history_id}}
    } @$ticket_history_ids;

    # return the filtered history_id's for the content to lookup
    return \@filtered_history_ids;
}

sub saveTicketHistory
{
    my $self = shift;
    my $ticket = shift;
    my $ticket_history_ids = shift;

    my $schema = $self->{dao}->{schema};

    $self->{dao}->connect();

    # Query existing history IDs for this ticket
    my $existing_history = $self->{dao}->query(
        "SELECT history_id FROM $schema.ticket_to_history_map WHERE ticket_id = ?",
        $ticket->{ticket_id}
    );

    # Create hash of existing history IDs
    my %existing_history_ids = map {$_->{history_id} => 1} @$existing_history;

    # Filter out history IDs that already exist
    my @new_history = grep {
        !exists $existing_history_ids{$_->{history_id}}
    } @$ticket_history_ids;

    # Only insert if we have new history IDs
    if (@new_history)
    {
        eval {
            $self->{dao}->batchInsert('ticket_to_history_map', \@new_history);
        };
        if ($@)
        {
            die "Failed to insert ticket history: $@";
        }
    }

    return 1;
}

sub getRequestTrackerQueues
{
    my $self = shift;

    # example: FOLIO,OpenRS,Enhancements
    my @queues = split /,/, $main::conf->{queues};

    return \@queues;
}

sub getRequestTrackerModules
{
    my $self = shift;

    my @modules = split /,/, $main::conf->{modules};

    return \@modules;
}

sub getTicketHistoryByTicketId
{
    my $self = shift;
    my $tickets = shift;

    # grab all the ticket history and save it to the database
    my @ticket_history_array = ();
    foreach my $ticket (@$tickets)
    {
        my $ticket_history = $main::api->getTicketHistoryById($ticket->{ticket_id});

        {push @ticket_history_array, @$ticket_history;}
        $main::dao->batchInsert('ticket_history', \@ticket_history_array);
    }

}

sub saveNewTicketIds
{
    my $self = shift;
    my $tickets = shift;

    my $schema = $self->{dao}->{schema};
    $main::log->addLogLine("Saving new ticket IDs to schema: $schema");
    $main::log->addLogLine("Total tickets received: " . scalar(@$tickets) . "");

    $self->{dao}->connect();
    $main::log->addLogLine("Database connection established");

    # query all the ticket id's from the database
    $main::log->addLogLine("Querying existing ticket IDs from database...");
    my $existing_tickets = $self->{dao}->query("SELECT ticket_id FROM $schema.tickets");
    $main::log->addLogLine("Found " . scalar(@$existing_tickets) . " existing tickets in database");

    if (scalar(@$existing_tickets) > 0)
    {
        $main::log->addLogLine("First few existing ticket IDs: ");
        my $count = min(5, scalar(@$existing_tickets));
        for (my $i = 0; $i < $count; $i++)
        {
            $main::log->addLogLine($existing_tickets->[$i]->{ticket_id} . ($i < $count - 1 ? ", " : ""));
        }
        $main::log->addLogLine("");
    }

    # create hash of existing ticket ids
    my %existing_ticket_ids = map {$_->{ticket_id} => 1} @$existing_tickets;
    $main::log->addLogLine("Created hash map of existing ticket IDs");

    # filter out tickets that already exist
    my @new_tickets = grep {
        !exists $existing_ticket_ids{$_->{ticket_id}}
    } @$tickets;

    $main::log->addLogLine("After filtering, found " . scalar(@new_tickets) . " new tickets to insert");

    if (scalar(@new_tickets) > 0)
    {
        $main::log->addLogLine("First few new ticket IDs to insert: ");
        my $count = min(5, scalar(@new_tickets));
        for (my $i = 0; $i < $count; $i++)
        {
            $main::log->addLogLine($new_tickets[$i]->{ticket_id} . ($i < $count - 1 ? ", " : ""));
        }
        $main::log->addLogLine("");
    }

    # only insert if we have new tickets
    if (@new_tickets)
    {
        $main::log->addLogLine("Inserting " . scalar(@new_tickets) . " new tickets into database...");
        eval {
            $self->{dao}->batchInsert('tickets', \@new_tickets);
            $main::log->addLogLine("New tickets inserted successfully");
        };
        if ($@)
        {
            $main::log->addLogLine("ERROR inserting new tickets: $@");
        }
    }
    else
    {
        $main::log->addLogLine("No new tickets to insert");
    }

    # Return the total number of tickets (both existing and new)
    my $total_tickets = scalar(@$tickets);
    $main::log->addLogLine("Total tickets (including both existing and new): $total_tickets");
    return $total_tickets;
}

sub saveTicketMetaData
{
    my $self = shift;
    my $ticket_meta = shift;

    my $schema = $self->{dao}->{schema};

    $self->{dao}->connect();

    # Query to get all fields from the existing metadata for this ticket_id
    my $existing_meta = $self->{dao}->query(
        "SELECT * FROM $schema.ticket_meta WHERE ticket_id = ?",
        $ticket_meta->{ticket_id}
    );

    # Only insert if we don't have this ticket's metadata already
    if (!@$existing_meta)
    {
        eval {
            $self->{dao}->insert('ticket_meta', $ticket_meta);
        };
        if ($@)
        {
            die "Insert failed: $@";
        }
    }
    # If we do have the ticket_meta already, compare and update if needed
    else
    {
        # Check if there are actual changes
        my $needs_update = 0;
        my $existing = $existing_meta->[0];

        # Compare fields
        foreach my $key (keys %$ticket_meta)
        {
            # Skip comparison if existing doesn't have this field
            next unless exists $existing->{$key};

            # Compare values, allowing for undefined values
            my $old_val = defined $existing->{$key} ? $existing->{$key} : '';
            my $new_val = defined $ticket_meta->{$key} ? $ticket_meta->{$key} : '';

            if ($old_val ne $new_val)
            {
                $needs_update = 1;
                last;
            }
        }

        # Only perform update if changes were detected
        if ($needs_update)
        {
            eval {
                $self->{dao}->update("$schema.ticket_meta", $ticket_meta, { ticket_id => $ticket_meta->{ticket_id} });
            };
            if ($@)
            {
                die "Update failed: $@";
            }
        }
    }

    return 1;
}

sub buildAISummaries
{
    my $self = shift;

    print "Building AI Summary \n";

    my $tickets = $self->{dao}->query("select ticket_id from request_tracker.ticket_meta where build_ai_summary = true;");

    foreach my $row (@$tickets)
    {

        my $ticket_id = $row->{ticket_id};
        print "Processing ticket: " . $ticket_id . " ";

        my $ticket = $self->{dao}->query("
        select t.ticket_id,
               tm.queue,
               tm.severity_level,
               tm.status,
               tm.created,
               tm.last_updated,
               tm.requesting_entity,
               tm.subject,
               t.description,
               t.content
        from request_tracker.ticket_content t
                 join request_tracker.ticket_meta tm on tm.ticket_id = t.ticket_id
        where t.content != 'This transaction appears to have no content'
          and t.description != 'Outgoing email recorded by RT_System'
        and tm.build_ai_summary
        and t.ticket_id = $ticket_id;")->[0];

        my $ticket_json = encode_json($ticket);
        my $categories = $self->getCategories();

        # I'm thinking we could fetch the wiki docs locally and then find matches, include the link in the $ticket
        # and the summaries wouldn't even bother with them. Same goes for other tickets right?
        my $prompt = $self->{ai}->buildPrompt($ticket_json, $categories);

        print "Sending prompt to AI ";

        my $start_time = time;
        my $summary = $self->{ai}->executeAPIRequest($prompt);
        my $total_time = time - $start_time;
        print "Total response time: $total_time/sec\n";

        # remove the ```json from the $summary. They wrap the json in markdown. Most models do this.
        $summary =~ s/```json//g;

        # remove the ``` from the $summary
        $summary =~ s/```//g;
        $summary = Encode::encode("UTF-8", $summary);

        my $summaryHash;

        # Try to decode the AI summary, if we can't decode it we skip it and move on to the next ticket. We'll pick it up again later.
        eval {$summaryHash = decode_json($summary);};
        if ($@)
        {
            warn "Failed to decode AI summary for ticket_id " . $ticket->{ticket_id} . ": $@";
            next;
        }

        # set some values, some of these we get back from the model but we use the original values
        $summaryHash->{model_used} = $self->{ai}->{model};
        $summaryHash->{ticket_id} = $ticket->{ticket_id};
        $summaryHash->{queue} = $ticket->{queue};
        $summaryHash->{requesting_entity} = $ticket->{requesting_entity};
        $summaryHash->{last_updated} = $ticket->{last_updated};
        $summaryHash->{created} = $ticket->{created};

        # embed the ai response
        $summaryHash->{embedding} = $self->{textEmbedding}->executeAPIRequest($summary);

        # Save the AI summary to the database within a transaction
        eval {
            my $dbh = $self->{dao}->connect();
            $dbh->begin;

            # Delete the old summary if it exists
            $self->{dao}->execute("DELETE FROM request_tracker.ticket_summary WHERE ticket_id = ?", $ticket->{ticket_id});

            # Insert the new summary
            $self->{dao}->insert('ticket_summary', $summaryHash);

            # Update the meta table to indicate that we have built the AI summary
            $self->{dao}->execute("UPDATE request_tracker.ticket_meta SET build_ai_summary = false WHERE ticket_id = ?", $ticket->{ticket_id});

            # Commit the transaction if everything succeeded
            $dbh->commit;
        };
        if ($@)
        {
            # Roll back the transaction if any operation failed
            eval {
                my $dbh = $self->{dao}->connect();
                $dbh->rollback;
            };
            warn "Failed to process ticket_id " . $ticket->{ticket_id} . ": $@";
        }

    }

    # check if we have any other AI summaries to build as it fails sometimes and we just move on.
    my $remaining_tickets = $self->{dao}->query("select ticket_id from request_tracker.ticket_meta where build_ai_summary = true;");
    if (@$remaining_tickets)
    {print "There are " . scalar(@$remaining_tickets) . " tickets remaining to build AI summaries for.\n";}
    else
    {print "All tickets have been processed for AI summaries.\n";}

    return $self;

}

sub getCategories
{
    my $self = shift;

    my $categories = "";

    # load categories from the db
    $categories = $self->{dao}->query("select distinct ts.category from request_tracker.ticket_summary ts;");

    # convert the array of hashes to a csv string
    $categories = join(',', map {$_->{category}} @$categories) if @$categories;

    return "[" . $categories . "]";
    # return $categories;
}

sub buildTextEmbeddings
{
    my $self = shift;
    my $text = shift;
    return $self->{textEmbedding}->executeAPIRequest($text);

}

sub processWikiPages
{
    my $self = shift;

    my $wiki = $self->fetchWikiPages();
    $wiki = $self->buildWikiPagesEmbeddings($wiki);

    $self->saveWikiEmbeddingsElasticSearch($wiki);

    return $self;

}

sub fetchWikiPages
{
    my $self = shift;

    my $data = $self->{wiki}->fetchAllWikiPagesWithContent();

    for my $page (@$data)
    {$page->{url} = "https://wiki.mobiusconsortium.org/w/index.php?curid=" . $page->{pageid} . "&action=raw";}

    return $data;
}

sub buildWikiPagesEmbeddings
{
    my $self = shift;
    my $wiki = shift;

    for my $page (@$wiki)
    {$page->{embedding} = $self->{textEmbedding}->executeAPIRequest($page->{content});}

    return $wiki;

}

sub buildTicketEmbeddings
{
    my $self = shift;

    my $tickets = $self->{dao}->query("SELECT * FROM request_tracker.ticket_meta tm where tm.embedding is null;");
    my $ticketCount = scalar(@$tickets);
    my $ticketIndex = 0;
    my $time_avg = 0;

    for my $meta (@$tickets)
    {
        my $start = time;

        # I need to get all the tickets for this meta ticketid
        my $ticket_content = $self->{dao}->query(
            "SELECT * FROM request_tracker.ticket_content tc where
                      tc.content != 'This transaction appears to have no content' AND
                      tc.description != 'Outgoing email recorded by RT_System' AND
            tc.ticket_id  = ?"
            , $meta->{ticket_id});

        my $ticket_content_text = $meta->{subject} . "\n";
        for my $content (@$ticket_content)
        {$ticket_content_text .= $content->{content} . "   \n";}

        my $embedding = $self->{textEmbedding}->executeAPIRequest($ticket_content_text);

        # now update this row in the database
        $self->{dao}->execute("UPDATE request_tracker.ticket_meta SET embedding = ? WHERE id = ?", $embedding, $meta->{id});

        my $end = time;
        my $time = ($end - $start) * 1000; # This gives time in milliseconds

        # Update the running average
        $ticketIndex++;
        $time_avg = (($time_avg * ($ticketIndex - 1)) + $time) / $ticketIndex;

        # Format to two decimal places
        $time_avg = sprintf("%.2f", $time_avg);

        # Calculate the estimated time remaining
        my $time_remaining = ($ticketCount - $ticketIndex) * ($time_avg / 1000) / 60;
        my $hours_remaining = $time_remaining / 60;

        $hours_remaining = sprintf("%.1f", $hours_remaining);
        $time_remaining = sprintf("%.1f", $time_remaining);

        print "Ticket: " . $ticketIndex . " of " . $ticketCount . " - Avg time:[$time_avg/ms] ETA: " . $time_remaining . " minutes [" . $hours_remaining . " hours]\n";

    }

    return $self;
}

sub getWikiPagesByEmbedding
{
    my $self = shift;
    my $embedding = shift;

    my $results = $self->{elasticSearch}->searchByEmbedding("wiki_pages", $embedding, "embedding");

    my @urls;
    for my $result (@{$results->{"hits"}->{"hits"}})
    {push @urls, $result->{_source}->{url};}

    # return \@urls;
    return encode_json(\@urls);
}

sub getSimilarTicketsByTicketID
{
    my $self = shift;
    my $ticket_id = shift;

    my $ticket = $self->{dao}->query("select * from request_tracker.ticket_meta tm where tm.ticket_id = ?", $ticket_id);
    return $self->getSimilarTicketsByEmbedding($ticket->[0]->{embedded});

}

sub getSimilarTicketsByEmbedding
{
    my $self = shift;
    my $embedding = shift;

    my $results = $self->{elasticSearch}->searchByEmbedding("ticket_embeddings", $embedding, "embedded");

    my @ticket_ids;
    for my $result (@{$results->{"hits"}->{"hits"}})
    {push @ticket_ids, $result->{_source}->{ticket_id};}

    return \@ticket_ids;
}

sub getFolioDocsByTicketID
{
    my $self = shift;
    my $ticket_id = shift;
    my $threshold = shift || 1.75; # High similarity threshold (range 0-2, with 2 being perfect match)
    my $max_results = shift || 5;  # Limit number of results

    # Get ticket embedding
    my $ticket = $self->{dao}->query("select * from request_tracker.ticket_meta tm where tm.ticket_id = ?", $ticket_id);

    # Return empty array if no ticket found
    return [] unless @$ticket;

    my $embedding = $ticket->[0]->{embedded};

    # Create a simpler additional query that won't exceed clause limits
    # Instead of extracting all words, focus on excluding empty documents
    my $additional_query = {
        bool => {
            must_not => [
                { term => { "content" => "" } } # Exclude empty documents
            ]
        }
    };

    # Get results with enhanced query parameters
    my $results = $self->{elasticSearch}->searchByEmbedding(
        "folio_docs",     # index
        $embedding,       # embedding vector
        "embedding",      # field
        $max_results * 2, # Get more results than we need for filtering
        $additional_query # Simple filter query
    );

    # Filter by threshold and build URL array
    my @urls;
    for my $row (@{$results->{hits}->{hits}})
    {
        if ($row->{_score} >= $threshold)
        {push @urls, $row->{_source}->{url};}

        # Break if we have enough results
        last if scalar(@urls) >= $max_results;
    }

    return \@urls;
}

sub createIndexSummaries
{
    my $self = shift;

    # Create mappings based on the database structure
    my $mappings = {
        properties => {
            ticket_id                    => { type => "integer" },
            model_used                   => { type => "keyword" },
            requesting_entity            => { type => "keyword" },
            queue                        => { type => "keyword" },
            status                       => { type => "keyword" },
            title                        => { type => "text" },
            summary                      => { type => "text" },
            summary_long                 => { type => "text" },
            contextual_details           => { type => "text" },
            contextual_technical_details => { type => "text" },
            keywords                     => { type => "keyword" },
            ticket_as_question           => { type => "text" },
            category                     => { type => "keyword" },
            key_points_discussed         => { type => "text" },
            data_patterns_or_trends      => { type => "text" },
            customer_sentiment           => { type => "keyword" },
            customer_sentiment_score     => { type => "integer" },
            wiki_url                     => { type => "keyword" },
            created                      => {
                type   => "date",
                format => "yyyy-MM-dd HH:mm:ss||strict_date_optional_time||epoch_millis"
            },
            last_updated                 => {
                type   => "date",
                format => "yyyy-MM-dd HH:mm:ss||strict_date_optional_time||epoch_millis"
            },
            embedded_ticket              => { type => "dense_vector", dims => 768 },
            embedded_summary             => { type => "dense_vector", dims => 768 }
        }
    };

    # Create the index with the specified mappings
    return $self->{elasticSearch}->createIndex("ticket_summary", $mappings);
}

# this creates the index for the ticket embeddings in elastic search.
sub createIndexTicketEmbeddings
{
    # I'll probably rename this
    my $self = shift;

    # Create mappings based on the database structure
    my $mappings = {
        properties => {
            ticket_id                    => { type => "integer" },
            model_used                   => { type => "keyword" },
            requesting_entity            => { type => "keyword" },
            queue                        => { type => "keyword" },
            status                       => { type => "keyword" },
            title                        => { type => "text" },
            summary                      => { type => "text" },
            summary_long                 => { type => "text" },
            contextual_details           => { type => "text" },
            contextual_technical_details => { type => "text" },
            keywords                     => { type => "keyword" },
            ticket_as_question           => { type => "text" },
            category                     => { type => "keyword" },
            key_points_discussed         => { type => "text" },
            data_patterns_or_trends      => { type => "text" },
            customer_sentiment           => { type => "keyword" },
            customer_sentiment_score     => { type => "integer" },
            wiki_url                     => { type => "keyword" },
            embedded_ticket              => { type => "dense_vector", dims => 768 },
            embedded_summary             => { type => "dense_vector", dims => 768 }
        }
    };

    # Create the index with the specified mappings
    return $self->{elasticSearch}->createIndex("ticket_embeddings", $mappings);
}

sub processFolioDocs
{
    my $self = shift;

    # Crawl the FOLIO docs
    my $docs = $self->crawlFolioDocs();

    # Embed the content
    $docs = $self->embedFolioDocs($docs);

    # Save the embedded content to ElasticSearch
    $self->saveFolioDocsEmbeddingsElasticSearch($docs);

    return $self;
}

# So we clone the docs and place them in the resource/folio/docs directory
# https://github.com/folio-org/docs
sub crawlFolioDocs
{
    my $self = shift;

    # my $path = $self->{docsPath};
    my $path = $main::conf->{folio_docs_path};

    my @docs;

    # Validate that the docs path exists
    die "Documentation path '$path' does not exist" unless -d $path;

    # Convert to absolute path for consistency
    my $absDocsPath = abs_path($path);

    # Use File::Find to traverse the directory structure
    find(
        {
            wanted   => sub {
                # Only process Markdown files
                return unless -f $_ && $_ =~ /\.md$/;

                # Get the full path to the file
                my $fullPath = $File::Find::name;

                # Get the relative path from the docs directory
                my $relPath = File::Spec->abs2rel($fullPath, $absDocsPath);

                # Create the URL based on the relative path
                # Replace backslashes with forward slashes for URLs on Windows
                $relPath =~ s/\\/\//g;

                # Generate URL according to the specified rules:
                # 1. Lowercase the path
                # 2. Replace spaces with hyphens
                # 3. Remove '_index' if path ends with it
                # 4. Remove .md extension and add trailing slash

                my $urlPath = $relPath;
                $urlPath = lc($urlPath);                  # Convert to lowercase
                $urlPath =~ s/ /-/g;                      # Replace spaces with hyphens
                $urlPath =~ s/_index\.md$//;              # Remove _index.md suffix
                $urlPath =~ s/\.md$//;                    # Remove .md extension
                $urlPath .= '/' unless $urlPath =~ /\/$/; # Add trailing slash if not present

                # Build the complete URL
                my $url = "https://docs.folio.org/docs/$urlPath";

                # Get the directory path for the document
                my $relDir = dirname($relPath);
                my $docDir = File::Spec->catdir($absDocsPath, $relDir);

                # read the contents of the file
                my $content = $self->{dao}->readFile($docDir . "/" . $_);

                # Create the document hash
                my $doc = {
                    'url'      => $url,
                    'docPath'  => $docDir,
                    'file'     => $_,        # The filename
                    'fullPath' => $fullPath, # The full path to the file
                    'relPath'  => $relPath,  # The relative path from docs directory
                    'content'  => $content,
                };

                # Add to our documents array
                push @docs, $doc;
            },
            no_chdir => 0,
        },
        $absDocsPath
    );

    return \@docs;
}

sub embedFolioDocs
{
    my $self = shift;
    my $docs = shift;

    for my $doc (@$docs)
    {

        # Skip empty documents
        next if ($doc->{content} eq '');

        print "Embedding content for FOLIO doc: $doc->{url}\n";

        # Embed the content
        my $embedding = $self->{textEmbedding}->executeAPIRequest($doc->{content});

        # Update the document hash with the embedding
        $doc->{embedding} = $embedding;
    }

    return $docs;

}

sub saveTicketSummaryElasticSearch
{
    my $self = shift;
    my $data_source = shift || 'database'; # 'database' or 'json'
    my $json_data = shift;

    my $index_name = 'ticket_summary';

    my $summaries;

    # Get data from database (original approach)
    $summaries = $self->{dao}->query("
            select tm.ticket_id,
                   tm.requesting_entity,
                   tm.queue,
                   tm.severity_level,
                   tm.status,
                   ts.title,
                   ts.summary,
                   ts.summary_long,
                   ts.contextual_details,
                   ts.contextual_technical_details,
                   ts.keywords,
                   ts.ticket_as_question,
                   ts.category,
                   ts.key_points_discussed,
                   ts.data_patterns_or_trends,
                   ts.customer_sentiment,
                   ts.customer_sentiment_score,
                   tm.created,
                   tm.last_updated,
                   ts.embedding
              from request_tracker.ticket_summary ts
              join request_tracker.ticket_meta tm on tm.ticket_id = ts.ticket_id
            order by tm.ticket_id asc;");

    print "Number of records to process: " . scalar(@$summaries) . "\n";
    die "No data to process" unless @$summaries;

    # Check if the index exists and delete it
    if ($self->{elasticSearch}->indexExists($index_name))
    {
        print "Deleting existing index...\n";
        $self->{elasticSearch}->deleteIndex($index_name);
    }

    # Define the mappings for the Elasticsearch index
    my $mappings = {
        properties => {
            id                           => {
                type => "integer"
            },
            ticket_id                    => {
                type => "integer"
            },
            model_used                   => {
                type => "keyword"
            },
            requesting_entity            => {
                type   => "keyword",
                fields => {
                    text => {
                        type => "text"
                    }
                }
            },
            queue                        => {
                type => "keyword"
            },
            status                       => {
                type => "keyword"
            },
            title                        => {
                type   => "text",
                fields => {
                    keyword => {
                        type         => "keyword",
                        ignore_above => 256
                    }
                }
            },
            summary                      => {
                type     => "text",
                analyzer => "standard"
            },
            summary_long                 => {
                type     => "text",
                analyzer => "standard"
            },
            contextual_details           => {
                type     => "text",
                analyzer => "standard"
            },
            contextual_technical_details => {
                type     => "text",
                analyzer => "standard"
            },
            keywords                     => {
                type       => "nested",
                properties => {
                    word  => {
                        type => "keyword"
                    },
                    score => {
                        type => "float"
                    }
                }
            },
            ticket_as_question           => {
                type     => "text",
                analyzer => "standard"
            },
            category                     => {
                type => "keyword"
            },
            key_points_discussed         => {
                type       => "nested",
                properties => {
                    point      => {
                        type => "text"
                    },
                    importance => {
                        type => "integer"
                    }
                }
            },
            data_patterns_or_trends      => {
                type     => "text",
                analyzer => "standard"
            },
            created                      => {
                type   => "date",
                format => "yyyy-MM-dd HH:mm:ss||strict_date_optional_time||epoch_millis"
            },
            last_updated                 => {
                type   => "date",
                format => "yyyy-MM-dd HH:mm:ss||strict_date_optional_time||epoch_millis"
            },
            customer_sentiment           => {
                type => "keyword"
            },
            customer_sentiment_score     => {
                type       => "integer",
                null_value => 0
            },
            embedding                    => {
                type => "dense_vector",
                dims => 768,
            }
        }
    };

    print "Creating Elasticsearch index '$index_name' with mappings...\n";
    $self->{elasticSearch}->createIndex($index_name, $mappings);

    # Pre-process data to ensure proper format for Elasticsearch
    foreach my $record (@$summaries)
    {
        # Handle keywords field - convert from JSON string to array if needed
        if (exists $record->{keywords} && !ref($record->{keywords}))
        {
            eval {
                $record->{keywords} = decode_json($record->{keywords});

                # Convert flat array to nested objects format required by ES mapping
                if (ref($record->{keywords}) eq 'ARRAY')
                {
                    my @keyword_objects = map {
                        {
                            word  => $_,
                            score => 1.0 # Default score
                        }
                    } @{$record->{keywords}};
                    $record->{keywords} = \@keyword_objects;
                }
            };
            if ($@)
            {
                warn "Error parsing keywords for ticket " . $record->{ticket_id} . ": $@";
                # Provide a default empty array to prevent errors
                $record->{keywords} = [];
            }
        }

        # Handle key_points_discussed field - convert from JSON string to array if needed
        if (exists $record->{key_points_discussed} && !ref($record->{key_points_discussed}))
        {
            eval {
                $record->{key_points_discussed} = decode_json($record->{key_points_discussed});

                # Convert flat array to nested objects format required by ES mapping
                if (ref($record->{key_points_discussed}) eq 'ARRAY')
                {
                    my @point_objects = map {
                        {
                            point      => $_,
                            importance => 1 # Default importance
                        }
                    } @{$record->{key_points_discussed}};
                    $record->{key_points_discussed} = \@point_objects;
                }
            };
            if ($@)
            {
                warn "Error parsing key_points_discussed for ticket " . $record->{ticket_id} . ": $@";
                # Provide a default empty array to prevent errors
                $record->{key_points_discussed} = [];
            }
        }

        # Ensure customer_sentiment_score is an integer
        if (exists $record->{customer_sentiment_score})
        {
            $record->{customer_sentiment_score} = int($record->{customer_sentiment_score});
        }

        # Ensure ticket_id is an integer
        if (exists $record->{ticket_id})
        {
            $record->{ticket_id} = int($record->{ticket_id});
        }

        # Process embedding field - convert from JSON string to array
        if (exists $record->{embedding} && !ref($record->{embedding}))
        {
            eval {
                # Remove any brackets and split by commas
                $record->{embedding} =~ s/^\[|\]$//g;
                my @embedding_array = split(/,\s*/, $record->{embedding});

                # Convert strings to numbers
                @embedding_array = map {0 + $_} @embedding_array;

                # Replace string with actual array
                $record->{embedding} = \@embedding_array;
            };
            if ($@)
            {
                warn "Error parsing embedding for ticket " . $record->{ticket_id} . ": $@";
                # Provide a default value to prevent errors
                delete $record->{embedding};
            }
        }

    }

    print "Importing " . scalar(@$summaries) . " records to Elasticsearch...\n";
    my $result = $self->{elasticSearch}->importData($index_name, $summaries);

    if ($result->{success})
    {
        print "Successfully imported " . $result->{imported} . " of " . $result->{total} . " records\n";
    }
    else
    {
        print "Import completed with errors\n";
    }

    return $self;
}

sub saveFolioDocsEmbeddingsElasticSearch
{
    my $self = shift;
    my $docs = shift;

    print "Saving FOLIO docs embeddings to Elasticsearch...\n";

    # Define the index name for FOLIO docs
    my $folio_index = 'folio_docs';

    # Check if the FOLIO docs index exists, and delete it if it does
    if ($self->{elasticSearch}->indexExists($folio_index))
    {
        print "Deleting existing FOLIO docs index...\n";
        $self->{elasticSearch}->deleteIndex($folio_index);
    }

    # Create mappings for FOLIO docs index
    my $mappings = {
        properties => {
            url       => { type => "keyword" },
            docPath   => { type => "keyword" },
            file      => { type => "keyword" },
            fullPath  => { type => "keyword" },
            relPath   => { type => "text" },
            content   => { type => "text" },
            embedding => { type => "dense_vector", dims => 768 }
        }
    };

    # Create the FOLIO docs index with the specified mappings
    print "Creating FOLIO docs index with mappings...\n";
    $self->{elasticSearch}->createIndex($folio_index, $mappings);

    # Prepare FOLIO docs data for import
    print "Preparing " . scalar(@$docs) . " FOLIO docs for import...\n";

    # Process each FOLIO doc to convert the embedding string to a proper array
    foreach my $doc (@$docs)
    {
        # Convert the embedding string to a proper array if it's a string
        if ($doc->{embedding} && !ref($doc->{embedding}))
        {
            # Remove the brackets and split by commas
            $doc->{embedding} =~ s/^\[|\]$//g;
            my @embedding_array = split(/,\s*/, $doc->{embedding});

            # Convert strings to numbers
            @embedding_array = map {0 + $_} @embedding_array;

            # Replace the string with the actual array
            $doc->{embedding} = \@embedding_array;
        }
    }

    # Import the FOLIO docs data to Elasticsearch
    if (@$docs)
    {
        print "Importing FOLIO docs data to Elasticsearch...\n";
        $self->{elasticSearch}->importData($folio_index, $docs);

        # Get document count after import
        my $doc_count = $self->{elasticSearch}->getDocCount($folio_index);
        print "FOLIO docs index now contains $doc_count documents\n";
    }
    else
    {
        print "No FOLIO docs data to import\n";
    }

    return $self;
}

sub saveTicketEmbeddingsElasticSearch
{
    my $self = shift;
    my $tickets = $self->{dao}->query("select tm.ticket_id, tm.embedding
                                       from request_tracker.ticket_meta tm
                                       where tm.embedding is not null;");

    print "Saving ticket embeddings to Elasticsearch...\n";

    # Define the index name for ticket embeddings
    my $ticket_index = 'ticket_embeddings';

    # Check if the ticket embeddings index exists, and delete it if it does
    if ($self->{elasticSearch}->indexExists($ticket_index))
    {
        print "Deleting existing ticket embeddings index...\n";
        $self->{elasticSearch}->deleteIndex($ticket_index);
    }

    # Create mappings for ticket embeddings index
    my $mappings = {
        properties => {
            ticket_id => { type => "keyword" },
            embedding => { type => "dense_vector", dims => 768 }
        }
    };

    # Create the ticket embeddings index with the specified mappings
    print "Creating ticket embeddings index with mappings...\n";
    $self->{elasticSearch}->createIndex($ticket_index, $mappings);

    # Prepare ticket data for import
    print "Preparing " . scalar(@$tickets) . " ticket embeddings for import...\n";

    # Process each ticket to convert the embedding string to a proper array
    foreach my $ticket (@$tickets)
    {
        # Convert the embedding string to a proper array if it's a string
        if ($ticket->{embedding} && !ref($ticket->{embedding}))
        {
            # Remove the brackets and split by commas
            $ticket->{embedding} =~ s/^\[|\]$//g;
            my @embedding_array = split(/,\s*/, $ticket->{embedding});

            # Convert strings to numbers
            @embedding_array = map {0 + $_} @embedding_array;

            # Replace the string with the actual array
            $ticket->{embedding} = \@embedding_array;
        }
    }

    # Import the ticket data to Elasticsearch
    if (@$tickets)
    {
        print "Importing ticket embeddings data to Elasticsearch...\n";
        $self->{elasticSearch}->importData($ticket_index, $tickets);

        # Get document count after import
        my $doc_count = $self->{elasticSearch}->getDocCount($ticket_index);
        print "Ticket embeddings index now contains $doc_count documents\n";
    }
    else
    {
        print "No ticket embeddings data to import\n";
    }

    return $self;
}

sub saveWikiEmbeddingsElasticSearch
{
    my $self = shift;
    my $wiki = shift;

    print "Saving wiki embeddings to Elasticsearch...\n";

    # Define the index name for wiki pages
    my $wiki_index = 'wiki_pages';

    # Check if the wiki index exists, and delete it if it does
    if ($self->{elasticSearch}->indexExists($wiki_index))
    {
        print "Deleting existing wiki index...\n";
        $self->{elasticSearch}->deleteIndex($wiki_index);
    }

    # Create mappings for wiki index
    my $mappings = {
        properties => {
            pageid    => { type => "keyword" },
            url       => { type => "keyword" },
            title     => { type => "text" },
            content   => { type => "text" },
            embedding => { type => "dense_vector", dims => 768 }
        }
    };

    # Create the wiki index with the specified mappings
    print "Creating wiki index with mappings...\n";
    $self->{elasticSearch}->createIndex($wiki_index, $mappings);

    # Prepare wiki data for import
    print "Preparing " . scalar(@$wiki) . " wiki pages for import...\n";

    # Process each wiki page to convert the embedding string to a proper array
    foreach my $page (@$wiki)
    {
        # Convert the embedding string to a proper array if it's a string
        if ($page->{embedding} && !ref($page->{embedding}))
        {
            # Remove the brackets and split by commas
            $page->{embedding} =~ s/^\[|\]$//g;
            my @embedding_array = split(/,\s*/, $page->{embedding});

            # Convert strings to numbers
            @embedding_array = map {0 + $_} @embedding_array;

            # Replace the string with the actual array
            $page->{embedding} = \@embedding_array;
        }
    }

    # Import the wiki data to Elasticsearch
    if (@$wiki)
    {
        print "Importing wiki data to Elasticsearch...\n";
        $self->{elasticSearch}->importData($wiki_index, $wiki);

        # Get document count after import
        my $doc_count = $self->{elasticSearch}->getDocCount($wiki_index);
        print "Wiki index now contains $doc_count documents\n";
    }
    else
    {
        print "No wiki data to import\n";
    }

    return $self;
}

1;