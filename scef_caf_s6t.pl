
use constant 
{ 
    SESSION => 1,     

    # CMD dictionary names
    CMD_NIR => 8388726,
    CMD_YY => 2,
    
    # AVP dictionary names
    AVP_External_Identifier => "External-Identifier",
    AVP_User_Identifier => "User-Identifier",
    AVP_Result_Code => "Result-Code",
   
    # diameter vendor ids
    TGPP_VENDOR_ID => 10415,

    #DCA App configuration data
    CFG_table => "ExternalIDs",
    # external id field name
    CFG_ext_id => "ExternalId",
    # imsi field name
    CFG_imsi => "IMSI"


};

my $DEBUG_ON = 1;
#$DEBUG_ON = undef;

use strict;

sub debug
{
    my $msg = shift;
    if(1 == $DEBUG_ON)
    {
        dca::application::logInfo("DEBUG: " . caller() . " " . $msg);
    }
}

sub cfg_extid_lookup
{
	my $ext_id = shift;
	debug "Entered lookup for ext id: $ext_id";
	debug "size of config: $#{$dca::appConfig{(CFG_table)}}";
	
	for my $i (0 .. $#{$dca::appConfig{(CFG_table)}} ) {
		debug "processing step $i for extid: $dca::appConfig{(CFG_table)}[$i]{(CFG_ext_id)}";
		debug "having imsi: $dca::appConfig{(CFG_table)}[$i]{(CFG_imsi)}";
		return $dca::appConfig{(CFG_table)}[$i]{(CFG_imsi)} if ( $ext_id =~ /$dca::appConfig{(CFG_table)}[$i]{(CFG_ext_id)}/)
	}
}

sub get_AVP_from_MSG
{
    my $msg = shift;
    my $key = shift;
    my $value = undef;

    # try to get the value from the avp
    if (!diameter::Message::avpExists($msg, $key)) 
    {
        debug "AVP $key does not exist in the diameter message";
    } else {

	    # AVP is in the message, we can use it
	    $value = diameter::Message::getAvpValue($msg, $key);
	    if(!defined($value))
	    {
		# could not get value from the request
		debug "Value of AVP $key value cannot not be read from diameter message";
	    }
    }
# return undef by default
  return $value;
 }

sub get_AVP_from_MSG_universal
{
    my $msg = shift;
    my $key = shift;
    my $value = undef;

	debug "Entered into get_AVP_from_MSG_universal() with key $key";

    # try to get the value from the avp
    if (!diameter::Message::avpExists($msg, $key)) 
    {
        debug "AVP $key does not exist in the diameter message";
    } else {

	    # AVP is in the message, we can use it

	# try it as grouped first

	$value = diameter::Message::getGroupedAvp($msg, $key);

	if (!defined($value)) {
	# if not defined - it's not grouped, trying to handle it as single
	    debug "AVP $key is not grouped";

	    $value = diameter::Message::getAvpValue($msg, $key);
	    if(!defined($value))
	    {
		# could not get value from the request
		debug "Value of AVP $key value cannot not be read from diameter message";
	    } else {
    		debug "AVP result: $value";
	    }
	} else {
    		debug "Group AVP result: $value";
	}	
    }
# return undef by default
  return $value;
 }

sub get_GAVP_from_MSG
{

    my $msg = shift;
    my $avp_name = shift;
    my $gAvp = undef;

    # try to get the value from the avp
    if (!diameter::Message::avpExists($msg, $avp_name)) 
    {
        debug "AVP $avp_name does not exist in the diameter message";
#        return undef;
    } else {

	    # AVP is in the message, we can use it
    	debug "GAVP is in the message, we can use it: $avp_name";
	$gAvp = diameter::Message::getGroupedAvp($msg, $avp_name);
    	debug "GAVP result: $gAvp";
    }

 return $gAvp

}

sub get_msg_cmd {

    my $msg = shift;

    # try to get the the diameter command code from the diameter message
    my $cmd = diameter::Message::commandCode($msg);

    if(!defined($cmd))
    {
        die "No command code in diameter message.";
    }
    debug "got message with CMD code: $cmd";
    
    return $cmd

}

sub get_msg_app_id {

    my $msg = shift;

    # try to get the the diameter command code from the diameter message
    my $appId = diameter::Message::applicationId($msg);

    if(!defined($appId))
    {
        die "No Application-Id in diameter message";
    }
    debug "got message with Application-id code: $appId";
    
    return $appId

}

sub send_answer {
     	debug "started send_answer()";

        my $ans = new dca::application::answer(2001,"DIAMETER_SUCCESS", TGPP_VENDOR_ID);

	my $err = diameter::Message::addAvpValue($ans, "User-name", "000000080032681");

     	debug "Answer: $ans";

    	if(!defined($err)){
     		debug "Error adding AVP value: $err";
	}

        dca::action::answer($ans);

}

sub exit_app()
{
     debug "started exit_app()";
     exit;
}

sub process_request()
{

    # diameter message is the first parameter
    my $param = shift;
	
    debug "started process_request()";

    # get the diameter message object
    my $msg = diameter::Param::message($param);
    die "Bad diameter message parameter process_request" unless defined ($msg);

    my $cmd = get_msg_cmd($msg);

    my $appId = get_msg_app_id($msg);


    if($cmd == CMD_NIR )
    {
     	debug "got message with CMD code NIR: $cmd";
        ### process NIR

	# get grouped User-Identifier
	my $user_id = get_AVP_from_MSG_universal($msg,AVP_User_Identifier);
     	debug "got return from get_AVP_from_MSG_universal: $user_id";

        if(defined($user_id))
	{	

		# get the externalID from grouped User-Identifier

# TODO: make as sub
		my $ext_id = diameter::GroupedAvp::getAvpValue($user_id,AVP_External_Identifier);

		if(!defined($ext_id))
		{
		    die "External ID is not present in message";
		}
     		debug "ExternalID: $ext_id";

		my $imsi = cfg_extid_lookup($ext_id);

		debug "IMSI matched: $imsi";

		send_answer();
	} else {
		debug "Userid is not parsed properly";
	}


    } else {
    	debug "got message with CMD code: $cmd";
    }
    dca::action::forward();
}

sub process_answer()
{

    my $param = shift;

    debug "started process_answer()";

    my $msg = diameter::Param::message($param) ;

    die "Missing Diameter message during process_answer" unless defined ($msg);

# my $err = diameter::Message::addAvpValue($msg, $avp_name, $avp_val);

    my $cmd = get_msg_cmd($msg);
    my $res_code = get_AVP_from_MSG_universal($msg,AVP_Result_Code);
 
    debug "got message with CMD code: $cmd";
    debug "result code: $res_code";

    dca::action::forward();
    exit_app();

}


