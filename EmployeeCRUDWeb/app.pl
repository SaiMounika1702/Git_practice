#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/config";
use lib "$FindBin::Bin/service";

use IO::Socket::INET;
use URI::Escape qw(uri_unescape);
use EmployeeService;

my $HOST = "127.0.0.1";
my $PORT = 8080;

my $service = EmployeeService->new();

eval { $service->test_connection(); };
if ($@) {
    print "Database connection failed:\n$@\n";
    print "Check config/Database.pm and make sure MySQL is running.\n";
    exit 1;
}

my $server = IO::Socket::INET->new(
    LocalAddr => $HOST,
    LocalPort => $PORT,
    Proto     => "tcp",
    Listen    => 10,
    Reuse     => 1
) or die "Cannot start web server on $HOST:$PORT: $!";

print "\nEmployee CRUD Web Application\n";
print "Database connection successful!\n";
print "Open http://localhost:$PORT in your browser.\n";
print "Press Ctrl+C to stop the server.\n\n";

while (my $client = $server->accept()) {
    eval {
        $client->autoflush(1);

        my $request = "";
        my $buffer = "";

        while ($request !~ /\r\n\r\n/s) {
            my $n = sysread($client, $buffer, 4096);
            last unless $n;
            $request .= $buffer;
            last if length($request) > 1000000;
        }

        my ($header, $body) = split(/\r\n\r\n/, $request, 2);
        $body //= "";

        my @lines = split(/\r\n/, $header // "");
        my ($method, $path) = split(/\s+/, $lines[0] // "GET / HTTP/1.1");

        my %headers;
        for my $line (@lines[1..$#lines]) {
            if ($line =~ /^([^:]+):\s*(.*)$/) {
                $headers{lc $1} = $2;
            }
        }

        if (($headers{"content-length"} // 0) > length($body)) {
            my $remaining = ($headers{"content-length"} // 0) - length($body);
            while ($remaining > 0) {
                my $n = sysread($client, $buffer, $remaining);
                last unless $n;
                $body .= $buffer;
                $remaining -= $n;
            }
        }

        my ($route, $query_string) = split(/\?/, $path, 2);
        my %params = parse_params($query_string // "");

        if ($method eq "POST") {
            my %post = parse_params($body);
            %params = (%params, %post);
        }

        my ($status, $content) = route_request($method, $route, \%params);

        my $response =
            "HTTP/1.1 $status\r\n" .
            "Content-Type: text/html; charset=UTF-8\r\n" .
            "Content-Length: " . length($content) . "\r\n" .
            "Connection: close\r\n\r\n" .
            $content;

        print $client $response;
    };

    if ($@) {
        my $error = html_page("Error", qq{
            <div class="alert error"><strong>Error:</strong><pre>@{[html_escape($@)]}</pre></div>
            <a class="btn" href="/">Back to Employees</a>
        });
        print $client "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: " . length($error) . "\r\nConnection: close\r\n\r\n$error";
    }

    close $client;
}

sub route_request {
    my ($method, $route, $p) = @_;

    if ($method eq "GET" && $route eq "/") {
        return ("200 OK", employee_list_page($p));
    }

    if ($method eq "GET" && $route eq "/new") {
        return ("200 OK", employee_form_page("Add Employee", "/create", undef));
    }

    if ($method eq "POST" && $route eq "/create") {
        validate_form($p);
        $service->add_employee($p->{name}, $p->{email}, $p->{salary});
        return redirect("/");
    }

    if ($method eq "GET" && $route eq "/edit") {
        my $employee = $service->get_employee($p->{id});
        die "Employee not found" unless $employee;
        return ("200 OK", employee_form_page("Edit Employee", "/update", $employee));
    }

    if ($method eq "POST" && $route eq "/update") {
        validate_form($p);
        $service->update_employee($p->{id}, $p->{name}, $p->{email}, $p->{salary});
        return redirect("/");
    }

    if ($method eq "POST" && $route eq "/delete") {
        $service->delete_employee($p->{id});
        return redirect("/");
    }

    return ("404 Not Found", html_page("Not Found", qq{
        <div class="alert error">Page not found.</div>
        <a class="btn" href="/">Back to Employees</a>
    }));
}

sub validate_form {
    my $p = shift;

    die "Name is required" unless defined $p->{name} && $p->{name} ne "";
    die "Email is required" unless defined $p->{email} && $p->{email} ne "";
    die "Salary is required" unless defined $p->{salary} && $p->{salary} =~ /^\d+(?:\.\d{1,2})?$/;
}

sub parse_params {
    my $input = shift // "";
    my %params;

    for my $pair (split /&/, $input) {
        next if $pair eq "";
        my ($key, $value) = split /=/, $pair, 2;
        $key //= "";
        $value //= "";
        $key = uri_unescape($key);
        $value =~ tr/+/ /;
        $value = uri_unescape($value);
        $params{$key} = $value;
    }

    return %params;
}

sub redirect {
    my $location = shift;
    my $content = qq{
        <!doctype html><html><head><meta http-equiv="refresh" content="0;url=$location"></head>
        <body><a href="$location">Continue</a></body></html>
    };

    return (
        "302 Found",
        $content
    );
}

sub employee_list_page {
    my $p = shift;
    my $employees = $service->get_employees();

    my $search = $p->{search} // "";
    my $search_lc = lc $search;

    my @filtered = grep {
        !$search ||
        index(lc($_->{name} // ""), $search_lc) >= 0 ||
        index(lc($_->{email} // ""), $search_lc) >= 0
    } @$employees;

    my $rows = "";

    for my $e (@filtered) {
        $rows .= qq{
            <tr>
                <td>$e->{id}</td>
                <td><strong>@{[html_escape($e->{name})]}</strong></td>
                <td>@{[html_escape($e->{email})]}</td>
                <td>₹ @{[html_escape($e->{salary})]}</td>
                <td>@{[html_escape($e->{created_at})]}</td>
                <td class="actions">
                    <a class="btn small" href="/edit?id=$e->{id}">Edit</a>
                    <form method="POST" action="/delete" class="inline"
                          onsubmit="return confirm('Delete this employee?');">
                        <input type="hidden" name="id" value="$e->{id}">
                        <button class="btn small danger" type="submit">Delete</button>
                    </form>
                </td>
            </tr>
        };
    }

    if (!$rows) {
        $rows = qq{
            <tr><td colspan="6" class="empty">No employees found.</td></tr>
        };
    }

    my $count = scalar @filtered;

    return html_page("Employee Management", qq{
        <div class="topbar">
            <div>
                <h1>Employee Management</h1>
                <p class="subtitle">$count employee(s)</p>
            </div>
            <a class="btn primary" href="/new">+ Add Employee</a>
        </div>

        <div class="toolbar">
            <form method="GET" action="/" class="search">
                <input type="text" name="search" placeholder="Search by name or email"
                       value="@{[html_escape($search)]}">
                <button class="btn" type="submit">Search</button>
                @{[$search ? qq{<a class="btn" href="/">Clear</a>} : ""]}
            </form>
        </div>

        <div class="card">
            <div class="table-wrap">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Name</th>
                            <th>Email</th>
                            <th>Salary</th>
                            <th>Created</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>$rows</tbody>
                </table>
            </div>
        </div>
    });
}

sub employee_form_page {
    my ($title, $action, $e) = @_;

    my $id = $e ? $e->{id} : "";
    my $name = $e ? $e->{name} : "";
    my $email = $e ? $e->{email} : "";
    my $salary = $e ? $e->{salary} : "";

    return html_page($title, qq{
        <div class="form-header">
            <div>
                <h1>$title</h1>
                <p class="subtitle">Enter employee information below.</p>
            </div>
            <a class="btn" href="/">← Back</a>
        </div>

        <div class="form-card">
            <form method="POST" action="$action">
                @{[$id ? qq{<input type="hidden" name="id" value="$id">} : ""]}

                <label>Employee Name</label>
                <input required type="text" name="name" value="@{[html_escape($name)]}" placeholder="Enter full name">

                <label>Email</label>
                <input required type="email" name="email" value="@{[html_escape($email)]}" placeholder="name&#64;example.com">

                <label>Salary</label>
                <input required type="number" step="0.01" min="0" name="salary" value="@{[html_escape($salary)]}" placeholder="Enter salary">

                <div class="form-actions">
                    <a class="btn" href="/">Cancel</a>
                    <button class="btn primary" type="submit">@{[$id ? "Update Employee" : "Add Employee"]}</button>
                </div>
            </form>
        </div>
    });
}

sub html_page {
    my ($title, $content) = @_;

    return qq{
<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>@{[html_escape($title)]} - Employee CRUD</title>
<style>
*{box-sizing:border-box}
body{margin:0;font-family:Inter,Segoe UI,Arial,sans-serif;background:#f6f8fb;color:#172033}
.header{height:64px;background:#1f3a68;color:#fff;display:flex;align-items:center;padding:0 32px;box-shadow:0 2px 8px #00000018}
.brand{font-size:20px;font-weight:700}
.container{max-width:1200px;margin:0 auto;padding:34px 24px}
.topbar,.form-header{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:24px}
h1{margin:0;font-size:30px;color:#1f3a68}
.subtitle{margin:7px 0 0;color:#64748b}
.btn{display:inline-flex;align-items:center;justify-content:center;text-decoration:none;border:1px solid #d8dee8;background:#fff;color:#334155;border-radius:7px;padding:10px 16px;font-weight:600;cursor:pointer;font-size:14px}
.btn:hover{background:#f1f5f9}
.btn.primary{background:#f26522;border-color:#f26522;color:#fff}
.btn.primary:hover{background:#dc5518}
.btn.danger{background:#fff1f0;border-color:#ffc9c3;color:#c0392b}
.btn.small{padding:7px 11px;font-size:13px}
.toolbar{display:flex;justify-content:space-between;margin-bottom:18px}
.search{display:flex;gap:8px;width:100%}
.search input{max-width:420px}
input{width:100%;padding:12px 13px;border:1px solid #d7dde7;border-radius:7px;background:#fff;font-size:15px;outline:none}
input:focus{border-color:#1f3a68;box-shadow:0 0 0 3px #1f3a6815}
.card,.form-card{background:#fff;border:1px solid #e1e6ee;border-radius:10px;box-shadow:0 2px 10px #1f293708}
.table-wrap{overflow:auto}
table{width:100%;border-collapse:collapse}
th{background:#f8fafc;color:#475569;font-size:13px;text-transform:uppercase;letter-spacing:.03em;text-align:left;padding:15px 16px;border-bottom:1px solid #e2e8f0}
td{padding:16px;border-bottom:1px solid #edf0f4;font-size:14px}
tr:last-child td{border-bottom:0}
.actions{white-space:nowrap;display:flex;gap:7px}
.inline{display:inline}
.empty{text-align:center;color:#64748b;padding:45px}
.form-card{max-width:650px;padding:28px}
.form-card label{display:block;font-weight:600;margin:0 0 7px;color:#334155}
.form-card input{margin-bottom:20px}
.form-actions{display:flex;justify-content:flex-end;gap:10px;margin-top:4px}
.alert{padding:15px;border-radius:8px;background:#fff}
.error{color:#991b1b;background:#fef2f2;border:1px solid #fecaca}
pre{white-space:pre-wrap}
\@media(max-width:700px){
.container{padding:22px 14px}.topbar,.form-header{align-items:flex-start;flex-direction:column}
h1{font-size:25px}.actions{flex-direction:column}
}
</style>
</head>
<body>
<header class="header"><div class="brand">Employee CRUD</div></header>
<main class="container">$content</main>
</body>
</html>
};
}

sub html_escape {
    my $s = shift // "";
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}
