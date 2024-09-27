#!/usr/bin/perl

use strict;
use Getopt::Std;
use vars qw/ %opt /;

my $url = "https://<zabbix server>/zabbix/api_jsonrpc.php"; # change <zabbix server> to your zabbix server
my $apitoken="<api token>"; # change <api token> to your API Token
my $maintenanceid;

#############
# Begin main
#
init();
my $groupname = $opt{s};
my $duration = $opt{d} || 10800;
my $maintname = $opt{n};

my $groupid = getgroupid($groupname);

if($opt{r}){
    print "Removing maintenance for group $groupname\n";
    getmaintid($groupid,$maintname);
    exit(0);
}else{
    print "Adding maintenance for group $groupname\n";
    addmaint($groupid,$duration,$maintname);
}
exit(0);

#########################
# Get command line input
#
sub init(){
    my $opt_string = 'hrs:d:n:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if $opt{h};
    usage() if !$opt{s};
    usage() if !$opt{n};
}
#####################
# Print script usage
#
sub usage(){
    print STDERR << "EOF";
usage: $0 [-hr] -s groupname [-d duration] -n name
 -h          : This (help) message
 -r          : Remove maintenance for specified host
 -s groupname : Hostgroupname in Zabbix
 -d          : Duration of maintenance in seconds. Leave blank to use default.
                 300 =  5 minutes
                1800 = 30 minutes
                3600 =  1 hour
               10800 =  3 hour (default)
 -n name     : unique identifier

-s and -n are required
 
example: $0 -s groupname -d 3600 -n backup
example: $0 -s groupname -r -n backup
EOF
    exit;
}

###################################################
# Subroutine to query Zabbix to get host id
#
sub getgroupid{
    my $groupname = shift;
    my $process = qq(curl -k -s -i -X POST -H 'Content-Type: application/json-rpc' -H 'Authorization: Bearer $apitoken' -d '{
    "params": {
        "filter": {
            "name": "$groupname"
        }
    },
    "jsonrpc": "2.0",
    "method": "hostgroup.get",
    "id": 2 }' $url);
    my $res = `$process`;
    chomp($res);

#    print "$res \n\n";
    my @output = split(/,/,$res);
    my $x=0;
    foreach(@output){
    if (($output[$x] =~ m/\"name\"/)&&($output[$x] =~ m/$groupname/)){
            $output[$x-1] =~ s/\[\{//g;
            $output[$x-1] =~ s/"//g;
            $output[$x-1] =~ s/groupid://g;
            $output[$x-1] =~ s/result://g;
            $output[$x-1] =~ s/\{//g;
            $groupid = $output[$x-1];
        }
        $x++;
    }
    if(!$groupid){
       print "WARNING - $groupname not found in maintenance for Zabbix.\n";
       exit(1);
    }
    print "Group ID: ".$groupid."\n";
    return $groupid
}


###################################################
# Subroutine to query Zabbix to get maintenance id
#
sub getmaintid{
    my $groupid = shift;
    my $maintname = shift;
    my $process = qq(curl -k -s -i -X POST -H 'Content-Type: application/json-rpc' -H 'Authorization: Bearer $apitoken' -d '{
    "params": [{
        "output": "extend",
        "selectHosts": "refer",
        "selectHostGroups": "refer",
        "groupids":[\"'.$groupid.'\"]
    }],
    "jsonrpc": "2.0",
    "method": "maintenance.get",
    "id": 2 }' $url);
    my $res = `$process`;
    chomp($res);
	
    my @output = split(/,/,$res);
    my $x=0;
    foreach(@output){
        if (($output[$x] =~ m/\"name\"/)&&($output[$x] =~ m/ID $maintname/)){
            $output[$x-1] =~ s/\[\{//g;
            $output[$x-1] =~ s/"//g;
            $output[$x-1] =~ s/maintenanceid://g;
            $output[$x-1] =~ s/result://g;
            $output[$x-1] =~ s/\{//g;
            $maintenanceid = $output[$x-1];
            remmaint($maintenanceid);
        }
        $x++;
    }
    if(!$maintenanceid){
       print "WARNING - $groupname not found in maintenance for Zabbix.\n";
       exit(1);
    }
}
 
#################################################
# Subroutine to add maintenance window to Zabbix
#
sub addmaint{
    $groupid = shift;
    $duration = shift;
    $maintname = shift;
    my $start = time();
    my $end = ($start + $duration);
   my $process = 'curl -k -s -i -X POST -H \'Content-Type: application/json-rpc\' -H \'Authorization: Bearer '.$apitoken.'\' -d "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"maintenance.create\",
    \"params\":[{
        \"groups\": [{\"groupid\": \"'.$groupid.'\"}],
        \"name\":\"000_Trigger Maintenance Mode with ID '.$maintname.' - '.$start.'\",
        \"maintenance_type\":\"0\",
        \"description\":\"000_Trigger Maintenance Mode for '.$groupname.' set by Action\",
        \"active_since\":\"'.$start.'\",
        \"active_till\":\"'.$end.'\",
        \"timeperiods\": [{
            \"timeperiod_type\": 0,
            \"start_date\": \"'.$start.'\",
            \"period\": '.$duration.'}]
        }],
    \"id\":3}" '.$url;
    my $res = `$process`;
    chomp($res);
 
    my @output = split(/,/,$res);
 
    foreach(@output){
    if ($_ =~ m/\"error/){
            print "$_\n";
        exit(1);
        }
        print "$_\n" if ($_ =~ m/\"result/);
    }
 
}
#################################################
# Subroutine to remove maintenance window from Zabbix
#
sub remmaint{
    $maintenanceid = shift;
    my $process = qq(curl -k -s -i -X POST -H 'Content-Type: application/json-rpc' -H 'Authorization: Bearer $apitoken' -d '{
    "jsonrpc":"2.0",
    "method":"maintenance.delete",
    "params":["$maintenanceid"],
    "id":2}' $url);
 
    my $res = `$process`;
    chomp($res);
 
    my @output = split(/,/,$res);
 
    foreach(@output){
        print "$_\n" if ($_ =~ m/\"error/);
        print "$_\n" if ($_ =~ m/\"result/);
    }
}
