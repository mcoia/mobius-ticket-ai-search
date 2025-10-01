package DAO;
use strict;
use warnings FATAL => 'all';
use DBIx::Simple;
use SQL::Abstract;
use JSON;
use Data::Dumper;

sub new
{
    my $class = shift;
    my ($dbname, $host, $username, $password, $schema) = @_;

    # Check for required parameters
    die "Missing required parameters. Usage: DAO->new(dbname, host, username, password, schema)"
        unless $dbname && $host && $username && $password && $schema;

    my $self = {
        'dbname'   => $dbname,
        'host'     => $host,
        'username' => $username,
        'password' => $password,
        'schema'   => $schema,
        'dbh'      => undef,
    };
    bless $self, $class;
    return $self;
}

sub connect
{
    my $self = shift;

    # $main::log->info("Connecting to database $self->{dbname} on $self->{host}");

    # Return existing connection if we have one
    return $self->{dbh} if $self->{dbh};

    $self->{dbh} = DBIx::Simple->connect(
        "dbi:Pg:dbname=$self->{dbname};host=$self->{host}",
        $self->{username},
        $self->{password},
        { RaiseError => 1, AutoCommit => 1 }
    );
    return $self->{dbh};
}

sub query
{

    my $self = shift;
    my $sql = shift;
    my @bind_values = @_;

    my $dbh = $self->connect(); # Add this line to ensure connection
    # my @rows = $dbh->query($sql, @bind_values)->hashes;
    my @rows = $self->{dbh}->query($sql, @bind_values)->hashes;
    return \@rows;
}

sub batchInsert
{
    my $self = shift;
    my $table = shift;
    my $records_array = shift;
    return unless @$records_array;

    my $schema = $self->{schema};
    my $dbh = $self->connect();
    my @columns = keys %{$records_array->[0]};

    # Create the prepared statement
    my $placeholders = join(',', map {'?'} @columns);
    my $columns_str = join(',', @columns);
    my $sql = "INSERT INTO $schema.$table ($columns_str) VALUES ($placeholders)";

    $dbh->begin;

    eval {
        my $sth = $dbh->dbh->prepare($sql);

        foreach my $record (@$records_array)
        {
            $sth->execute(map {$record->{$_}} @columns);
        }

        $dbh->commit;
    };
    if ($@)
    {
        $dbh->rollback;
        die "Batch insert failed: $@";
    }

    return 1;
}

sub insert
{
    my $self = shift;
    my $table = shift;
    my $record = shift;

    # Clone the record to avoid modifying the original
    my %record_copy = %$record;

    # Convert array fields to JSON strings for storage
    if ($record_copy{keywords} && ref($record_copy{keywords}) eq 'ARRAY')
    {
        $record_copy{keywords} = encode_json($record_copy{keywords});
    }
    if ($record_copy{key_points_discussed} && ref($record_copy{key_points_discussed}) eq 'ARRAY')
    {
        $record_copy{key_points_discussed} = encode_json($record_copy{key_points_discussed});
    }

    my $full_table_name = "$self->{schema}.$table";
    my $dbh = $self->connect();

    eval {
        # print "Inserting record into $full_table_name\n";
        # print "Record: " . Dumper(\%record_copy) . "\n";
        $dbh->insert($full_table_name, \%record_copy);
    };
    if ($@)
    {
        die "Insert failed: $@";
    }

    return 1;
}

sub execute
{
    my $self = shift;
    my $sql = shift;
    my @bind_values = @_;

    my $dbh = $self->connect();
    return $self->{dbh}->query($sql, @bind_values);
}

sub update
{
    my ($self, $table, $record, $where) = @_;
    my $dbh = $self->connect();

    eval {
        $dbh->update($table, $record, $where);
    };
    if ($@)
    {
        die "Update failed: $@";
    }

    return 1;
}

sub delete
{
    my ($self, $table, $where) = @_;
    my $dbh = $self->connect();

    eval {
        $dbh->delete($table, $where);
    };
    if ($@)
    {
        die "Delete failed: $@";
    }

    return 1;
}

sub DESTROY
{
    my $self = shift;
    $self->{dbh}->disconnect if $self->{dbh};
}

sub readFile
{
    my $self = shift;
    my $file = shift;

    # Check if file exists first
    if (!-e $file)
    {
        # Return empty string instead of dying
        return '';
    }

    # Proceed with file reading if it exists
    open(my $fh, '<', $file) or return ''; # Return empty string on any open error
    my $content = do {
        local $/;
        <$fh>
    };
    close($fh);

    return $content;
}

1;