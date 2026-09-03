EMPLOYEE CRUD WEB APPLICATION
============================

This is a browser-based Perl + MySQL CRUD application.

It does NOT require DBD::mysql.

Requirements:
- Perl (Strawberry Perl recommended)
- MySQL Server
- mysql.exe available in PATH

PROJECT STRUCTURE
-----------------
EmployeeCRUDWeb/
  app.pl
  config/
    Database.pm
  service/
    EmployeeService.pm
  sql/
    setup.sql
  public/

SETUP
-----

1. Open this folder in VS Code.

2. Edit:
   config\Database.pm

   Change:
   our $PASSWORD = "YOUR_MYSQL_PASSWORD";

   to your actual MySQL root password.

3. Create the database/table.

   In PowerShell:
   Get-Content .\sql\setup.sql | mysql -u root -p

4. Verify:
   mysql -u root -p -e "USE employee_crud; SHOW TABLES;"

   You should see:
   employees

5. Start the web application:

   perl app.pl

6. Open a browser and go to:

   http://localhost:8080

WEB CRUD
--------
- View employees
- Search employees
- Add employee
- Edit employee
- Delete employee

STOP SERVER
-----------
Press Ctrl+C in the VS Code terminal.

IMPORTANT
---------
Keep the terminal running while using the website.

If port 8080 is already in use, open app.pl and change:
my $PORT = 8080;
to another port, such as 8090.
Then open http://localhost:8090.
