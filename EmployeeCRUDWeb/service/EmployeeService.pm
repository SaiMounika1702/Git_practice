package EmployeeService;

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/config";
use IPC::Open3;
use Symbol qw(gensym);
use Database;

sub new {
    my $class = shift;
    return bless {
        host     => $Databasegbrbbgb::HOST,
        port     => $Database::PORT,
        database => $Database::DATABASE,
        username => $Database::USERNAME,
        password => $Database::stratus
    }, $class;
}

sub escape_sql {
    my ($self, $value) = @_;
    $value //= "";
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    return $value;
}

sub run_mysql {
    my ($self, $query, $select_mode) = @_;

    my @cmd = (
        "mysql",
        "--host=$self->{host}",
        "--port=$self->{port}",
        "--user=$self->{username}",
        "--password=$self->{password}",
        "--database=$self->{database}"
    );

    push @cmd, "--batch", "--skip-column-names", "--raw" if $select_mode;
    push @cmd, "-e", $query;

    my $stderr = gensym;
    my $pid = open3(my $stdin, my $stdout, $stderr, @cmd);
    close $stdin;

    my $output = do { local $/; <$stdout> // "" };
    my $error  = do { local $/; <$stderr> // "" };

    waitpid($pid, 0);
    my $exit_code = $? >> 8;

    die "Database error:\n$error$output" if $exit_code != 0;
    return $output;
}

sub test_connection {
    my $self = shift;
    my $out = $self->run_mysql("SELECT 1", 1);
    return $out =~ /1/;
}

sub add_employee {
    my ($self, $name, $email, $salary) = @_;
    $name = $self->escape_sql($name);
    $email = $self->escape_sql($email);
    $salary = $self->escape_sql($salary);

    $self->run_mysql(
        "INSERT INTO employees (name,email,salary) VALUES ('$name','$email','$salary')",
        0
    );
}

sub get_employees {
    my $self = shift;
    my $out = $self->run_mysql(
        "SELECT id,name,email,salary,created_at FROM employees ORDER BY id DESC",
        1
    );

    my @rows;
    for my $line (split /\r?\n/, $out) {
        next if $line =~ /^\s*$/;
        my @f = split /\t/, $line, -1;
        push @rows, {
            id => $f[0], name => $f[1], email => $f[2],
            salary => $f[3], created_at => $f[4]
        };
    }
    return \@rows;
}

sub get_employee {
    my ($self, $id) = @_;
    die "Invalid employee ID" unless defined $id && $id =~ /^\d+$/;

    my $out = $self->run_mysql(
        "SELECT id,name,email,salary,created_at FROM employees WHERE id=$id",
        1
    );

    return undef if $out =~ /^\s*$/;

    my @f = split /\t/, (split(/\r?\n/, $out))[0], -1;
    return {
        id => $f[0], name => $f[1], email => $f[2],
        salary => $f[3], created_at => $f[4]
    };
}

sub update_employee {
    my ($self, $id, $name, $email, $salary) = @_;
    die "Invalid employee ID" unless defined $id && $id =~ /^\d+$/;

    $name = $self->escape_sql($name);
    $email = $self->escape_sql($email);
    $salary = $self->escape_sql($salary);

    $self->run_mysql(
        "UPDATE employees SET name='$name', email='$email', salary='$salary' WHERE id=$id",
        0
    );
}

sub delete_employee {
    my ($self, $id) = @_;
    die "Invalid employee ID" unless defined $id && $id =~ /^\d+$/;
    $self->run_mysql("DELETE FROM employees WHERE id=$id", 0);
}

1;
