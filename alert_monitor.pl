#!/usr/bin/perl -w

#=====================================================================================#
# This script reads alert log messages from Oracle table x$dbgalertext                #
# (>=11.2.0.1 only) generated in last 6 minutes. The script is scheduted to run each  #
# 5 minutes, so some alerts can be reported twice. I think it is OK.                  #
#                                                                                     #
# Crontab command:                                                                    #
# 3,8,13,18,23,28,33,38,43,48,53,58 * * * * . /home/oracle/scripts/.bash_profile_cron #
# sdavzse1 sdavzse1a;/home/oracle/scripts/alert_monitor.pl >                          #
# /home/oracle/scripts/log/alert_monitor_sdavzse1.log 2>&1                            #
#                                                                                     #
# Script reads corresponding section (based on DB name and server name) from          #
# configuration file ./config/alert_monitor.conf, where 'config' is                   #
# subdirectory of the script home directory.                                          #
#............................... configuration file ..................................#
# [STPHORACLEDB04_NVCSEA3]                                                            #
# # List messages which can be ignored:                                               #
# # WARNING: inbound connection timed out (ORA-3136)                                  #
# # ORA-1652: unable to extend temp segment                                           #
# # ORA-28500: connection from ORACLE to a non-Oracle system returned this message:   #
# # ORA-00235: control file read without a lock inconsistent due to concurrent update #
# errors_exclude=(ORA-3136|ORA-1654|ORA-28500|ORA-00235)                              #
# errors_include=(ORA-|TNS-|crash|Error)                                              #
#                                                                                     #
# [STPHORACLEDB04_SDAVZSE1]                                                           #
# # List messages which can be ignored:                                               #
# # WARNING: inbound connection timed out (ORA-3136)                                  #
# # ORA-1652: unable to extend temp segment                                           #
# # ORA-28500: connection from ORACLE to a non-Oracle system returned this message:   #
# # ORA-00235: control file read without a lock inconsistent due to concurrent update #
# errors_exclude=(ORA-3136|ORA-1654|ORA-28500|ORA-00060|ORA-00235)                    #
# errors_include=(ORA-|TNS-|crash|Error)                                              #
#.....................................................................................#
# After reading all messages, generated in last 6 minutes, the messages are filtered  #
# using 'include' and 'exclude' patterns. Result is written to log file and e-mailed  #
# to DBA team.                                                                        #
#=====================================================================================#

use strict;
use warnings;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use FileHandle;
use File::Basename;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

#--------------------------------------------------------------#
# DB name and server name should be UPPER case. This is needed #
# to read corresponding section from configuration file        #
#--------------------------------------------------------------#
my $db_name        = uc $ENV{ORACLE_SID};
my $server_name    = uc $ENV{ORACLE_HOST_NAME};
my $config_db_name = $server_name.'_'.$db_name;

#----------------------------------------------------#
# Call procedure from my_library.pl                  #
# Get file names, check for double execution         #
# and return reference hash with config parameters   #
# It does not check for double execution on Windows. #
#----------------------------------------------------#
my $config_params_ref = GetConfig();

#------------------------------------------#
# Read configuration file and check format #
#------------------------------------------#
my $errors_include = $config_params_ref->{$config_db_name}{'errors_include'};
my $errors_exclude = $config_params_ref->{$config_db_name}{'errors_exclude'};
if (( !defined $errors_include ) or ( !defined $errors_exclude ))
{
    print "Check configuration file. Some parameter was not defined.\n";
    exit 1;
}

#-------------------------------#
# Select data from the database #
#-------------------------------#
# Connect to the database. Call function from my_library.pl
my $dbh = Connect2Oracle ($db_name);

# HARD-CODED:
# Query to select alert messages generated in last 6 minutes
my $sql01 = qq
{
select originating_timestamp, message_text
  from x\$dbgalertext
 where originating_timestamp > sysdate - 6/1440
 order by 1
};

# Run the query and receive pointer to array of references
my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

#-----------------------------------------------------------------------------#
# Filter alert messages according INCLUDE and EXCLUDE from configuration file #
# Print errors in log file and send e-mail to DBA team                        #
#-----------------------------------------------------------------------------#
my $message = '';
my $ii = 0;
for (@$result_array_ref)
{
    # Filter errors
    if (    ($result_array_ref->[$ii][1] =~ m/$errors_include/i)
        and ($result_array_ref->[$ii][1] !~ m/$errors_exclude/i)
    )
    {
        # Print timestamp and message text into log file
        my $the_line = "$result_array_ref->[$ii][0] $result_array_ref->[$ii][1]";
        print $the_line;

        # Prepare message for e-mail
        $message .= $the_line;
    }

    $ii++;
}

#
# Send e-mail if there are errors
#
if ( $message ne '')
{
    SendAlert ( $server_name,
                "Errors in Oracle Alert Log $db_name on $server_name.",
                $message );
}
else
{
    # If there are no alerts in alert log file, this should be the only
    # output line in the script log:
    print "No errors found\n";
}

exit;
