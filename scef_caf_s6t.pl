#!/usr/bin/env perl
#===============================================================================
#
#         FILE: new.pl
#
#        USAGE: ./new.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Denis Gudtsov (DG),
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 26.08.2019 13:55:59
#     REVISION: ---
#===============================================================================

use constant {
    SESSION => 1,

    # CMD dictionary names
    CMD_NIR => 8388726,

    #    CMD_YY => 2,

    # AVP dictionary names
    AVP_External_Identifier         => "External-Identifier",
    AVP_User_Identifier             => "User-Identifier",
    AVP_Result_Code                 => "Result-Code",
    AVP_NIDD_Authorization_Response => "NIDD-Authorization-Response",
    AVP_MSISDN                      => "MSISDN",
    AVP_User_Name                   => "User-Name",

    AVP_Session_Id         => "Session-Id",
    AVP_Destination_Host   => "Destination-Host",
    AVP_Destination_Realm  => "Destination-Realm",
    AVP_Origin_Host        => "Origin-Host",
    AVP_Origin_Realm       => "Origin-Realm",
    AVP_Supported_Features => "Supported-Features",
    AVP_Auth_Session_State => "Auth-Session-State",

    Result_Code => 2001,
    Result_Str  => "DIAMETER_SUCCESS",

    # diameter vendor ids
    TGPP_VENDOR_ID => 10415,

    #DCA App configuration data
    CFG_table => "ExternalIDs",

    # external id field name
    CFG_ext_id => "ExternalId",

    # imsi field name
    CFG_imsi => "IMSI",

    # msisdn field name
    CFG_msisdn => "MSISDN"

};

my $DEBUG_ON = 1;

#$DEBUG_ON = undef;

use strict;
use warnings;
use utf8;

#use Data::Dumper;

sub debug {
    my $msg = shift;
    if ( 1 == $DEBUG_ON ) {
        dca::application::logInfo( "DEBUG: " . caller() . " " . $msg );
    }
	return;
}

sub cfg_extid_lookup {

    # external lookup in the CFG_table
    # by key in column CFG_ext_id
    # returned value from CFG_imsi column
    my $ext_id = shift;
    debug "Entered lookup for ext id: $ext_id";
    debug "size of config: $#{$dca::appConfig{(CFG_table)}}";

    for my $i ( 0 .. $#{ $dca::appConfig{ (CFG_table) } } ) {
        debug "processing step $i for extid: $dca::appConfig{(CFG_table)}[$i]{(CFG_ext_id)}";
        debug "having imsi: $dca::appConfig{(CFG_table)}[$i]{(CFG_imsi)} msisdn: $dca::appConfig{(CFG_table)}[$i]{(CFG_msisdn)}";
        return (
            $dca::appConfig{ (CFG_table) }[$i]{ (CFG_imsi) },
            $dca::appConfig{ (CFG_table) }[$i]{ (CFG_msisdn) }
        ) if ( $ext_id =~ /$dca::appConfig{(CFG_table)}[$i]{(CFG_ext_id)}/ );
    }
	return;
}

sub get_AVP_from_MSG_universal {
    my $msg   = shift;
    my $key   = shift;
    my $value = undef;

    debug "Entered into get_AVP_from_MSG_universal() with key $key";

    # try to get the value from the avp
    if ( !diameter::Message::avpExists( $msg, $key ) ) {
        debug "AVP $key does not exist in the diameter message";
    }
    else {

        # AVP is in the message, we can use it

        # try it as grouped first

        $value = diameter::Message::getGroupedAvp( $msg, $key );

        if ( !defined($value) ) {

            # if not defined - it's not grouped, trying to handle it as single
            debug "AVP $key is not grouped";

            $value = diameter::Message::getAvpValue( $msg, $key );
            if ( !defined($value) ) {

                # could not get value from the request
                debug "Value of AVP $key value cannot not be read from diameter message";
            }
            else {
                debug "AVP result: $value";
            }
        }
        else {
            debug "Group AVP result: $value";
        }
    }

    # return undef by default
    return $value;
}

sub get_AVP_from_Grouped {
    my $gavp  = shift;
    my $key   = shift;
    my $value = undef;

    debug "Entered into get_AVP_from_MSG_universal() with key $key";

    $value = diameter::GroupedAvp::getAvpValue( $gavp, $key );

    if ( !defined($value) ) {
        debug "key $key is not present in GAVP";
    }
    else {
        debug "AVP $key value: $value";
    }

    return $value;
}

sub get_msg_cmd {

    my $msg = shift;

    # try to get the the diameter command code from the diameter message
    my $cmd = diameter::Message::commandCode($msg);

    if ( !defined($cmd) ) {
        die "No command code in diameter message.";
    }
    debug "got message with CMD code: $cmd";

    return $cmd

}

sub get_msg_app_id {

    my $msg = shift;

    # try to get the the diameter command code from the diameter message
    my $appId = diameter::Message::applicationId($msg);

    if ( !defined($appId) ) {
        die "No Application-Id in diameter message";
    }
    debug "got message with Application-id code: $appId";

    return $appId

}

#-------------------------------------------------------------------------------
#  Preparing answer procedude
#-------------------------------------------------------------------------------
sub send_answer {

    my %subs = %{ shift() };
    my $msg  = shift;
    my %response;

    # original AVPs in request that need to be copied into answer
    my @req_AVPs = ( AVP_Session_Id, AVP_Destination_Host,
        AVP_Destination_Realm, AVP_Origin_Host,
        AVP_Origin_Realm,      AVP_Supported_Features,
        AVP_Auth_Session_State
    );

    debug "started send_answer()";

    debug "subs: " . values %subs;

    # replicating AVPs from request into %response
    foreach my $key (@req_AVPs) {
        my $value = get_AVP_from_MSG_universal( $msg, $key );
        ( defined $value ) ? ( $response{ ($key) } = $value ) : debug "$key is not parsed properly";
    }

    # exchanging orig and dest hosts and realms
    ( $response{ (AVP_Destination_Host) }, $response{ (AVP_Origin_Host) } ) =
      ( $response{ (AVP_Origin_Host) }, $response{ (AVP_Destination_Host) } );
    ( $response{ (AVP_Destination_Realm) }, $response{ (AVP_Origin_Realm) } ) =
      ( $response{ (AVP_Origin_Realm) }, $response{ (AVP_Destination_Realm) } );

    foreach my $key ( AVP_Destination_Host, AVP_Origin_Host,
        AVP_Destination_Realm, AVP_Origin_Realm
      )
    {
        debug "hash key: $key has value: $response{($key)}";
    }

    debug "hash array populating has been done";

    my $ans = new dca::application::answer( Result_Code, Result_Str, "" );
    diameter::Message::setAddAvpValue( $ans, AVP_Result_Code, Result_Code );

    foreach my $key ( keys %response ) {
        ( diameter::Message::setAddAvpValue( $ans, $key, $response{$key} ) )
          ? ( debug "added $key into response: $response{$key}" )
          : ( debug "error adding $key into response" );
    }

    my $avp_nidd_response =
      diameter::Message::addGroupedAvp( $ans, AVP_NIDD_Authorization_Response );
    if ( defined $avp_nidd_response ) {
        debug "sucessfully created Grouped AVP_NIDD_Authorization_Response";
        debug "adding keys into NIDD response: " . keys %subs;
        print_hash(%subs);

        foreach my $key ( keys %subs ) {
            diameter::GroupedAvp::addAvpValue( $avp_nidd_response, $key,
                $subs{$key} )
              ? ( debug "added $key into NIDD response: $subs{$key}" )
              : ( debug "error adding $key into NIDD response" );
        }

        debug "NIDD reponse done, GAVP: $avp_nidd_response";
    }
    else {
        debug "Failed to add AVP_NIDD_Authorization_Response";
    }

    #	debug Dumper($avp_response);

    debug "Full Answer: $ans";

    #	debug Dumper($ans);

    #    	if(!defined($err)){
    #     		debug "Error adding AVP value: $err";
    #	}

    dca::action::answer($ans);
	return;
}

#----------------------------------------------------------------------
#  subroutine : print_hash
#----------------------------------------------------------------------
sub print_hash {
    my $hashref = shift;    # 1. parameter : hash reference
    debug "\n";
    while ( my ( $key, $value ) = each %$hashref ) {
        debug "'$key'\t=>\t'$value'\n";
    }                       # -----  end while  -----
	return;
}    # ----------  end of subroutine print_hash  ----------

sub exit_app() {
    debug "started exit_app()";
    exit;
}

#
#  Subroutine for processing a request message
#
sub process_request() {

    # diameter message is the first parameter
    my $param = shift;

    debug "started process_request()";

    # get the diameter message object
    my $msg = diameter::Param::message($param);
    die "Bad diameter message parameter process_request" unless defined($msg);

    my $cmd = get_msg_cmd($msg);

    my $appId = get_msg_app_id($msg);

    if ( $cmd == CMD_NIR ) {
        debug "got message with CMD code NIR: $cmd";
        ### process NIR

        # get grouped User-Identifier
        my $user_id = get_AVP_from_MSG_universal( $msg, AVP_User_Identifier );
        debug "got return from get_AVP_from_MSG_universal: $user_id";

        if ( defined($user_id) ) {

            # get the externalID from grouped User-Identifier

            my $ext_id =
              get_AVP_from_Grouped( $user_id, AVP_External_Identifier );

            debug "ExternalID: $ext_id";

            # sub returns imsi & msisdn
            my ( $imsi, $msisdn ) = cfg_extid_lookup($ext_id);
            debug "Matched IMSI: $imsi MSISDN: $msisdn";

            # populate subscriber data
            my %subscriber = (
                (AVP_MSISDN)              => $msisdn,
                (AVP_User_Name)           => $imsi,
                (AVP_External_Identifier) => $ext_id
            );

            # pass subscriber data and AVPs from original request
            send_answer( \%subscriber, $msg );

        }
        else {
            debug "Userid is not parsed properly";
        }

    }
    else {
        debug "got message with CMD code: $cmd";
    }

    # default action
    dca::action::forward();
    exit_app();
	return;
}

#
#  Subroutine for processing an answer message
#
sub process_answer() {

    my $param = shift;

    debug "started process_answer()";

    my $msg = diameter::Param::message($param);

    die "Missing Diameter message during process_answer" unless defined($msg);

    # my $err = diameter::Message::addAvpValue($msg, $avp_name, $avp_val);

    my $cmd = get_msg_cmd($msg);
    my $res_code = get_AVP_from_MSG_universal( $msg, AVP_Result_Code );

    debug "got message with CMD code: $cmd";
    debug "result code: $res_code";

    dca::action::forward();
    exit_app();
	return;
}

