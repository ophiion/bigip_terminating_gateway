 when RULE_INIT {
    #set static::sb_debug to 2 if you want to enable logging to troubleshoot this iRule, 1 for informational messages, otherwise set to 0
    set static::sb_debug 0
    if {$static::sb_debug > 1} { log local0. "rule init" }
}

when CLIENTSSL_HANDSHAKE {
   if { [SSL::extensions exists -type 0] } {
       binary scan [SSL::extensions -type 0] {@9A*} sni_name
       if {$static::sb_debug > 1} { log local0. "sni name: ${sni_name}"}
       
    }
    # use the ternary operator to return the servername conditionally
    if {$static::sb_debug > 1} { log local0. "sni name: [expr {[info exists sni_name] ? ${sni_name} : {not found} }]"}
}

when CLIENTSSL_CLIENTCERT {
  if {$static::sb_debug > 1} {log local0. "In CLIENTSSL_CLIENTCERT"}
  set client_cert [SSL::cert 0]
}

when HTTP_REQUEST {
    set serial_id ""
    set spiffe ""
    set log_prefix "[IP::remote_addr]:[TCP::remote_port clientside] [IP::local_addr]:[TCP::local_port clientside]"
    if { [SSL::cert count] > 0 } {
        HTTP::header insert "X-ENV-SSL_CLIENT_CERTIFICATE" [X509::whole [SSL::cert 0]]
        set spiffe [findstr [X509::extensions [SSL::cert 0]] "Subject Alternative Name" 39 ","]
        if {$static::sb_debug > 1} { log local0. "<$log_prefix>: SAN: $spiffe"}
        set serial_id [X509::serial_number $client_cert]
        if {$static::sb_debug > 1} { log local0. "<$log_prefix>: Serial_ID: $serial_id"}
    }
    if {$static::sb_debug > 1} { log local0.info "here is spiffe:  $spiffe" }
    set RPC_HANDLE [ILX::init "SidebandPlugin" "SidebandExt"]
    if {[catch {ILX::call $RPC_HANDLE "func" $sni_name $spiffe $serial_id} result]} {
        if {$static::sb_debug > 1} { log local0.error  "Client - [IP::client_addr], ILX failure: $result"}
        HTTP::respond 500 content "Internal server error: Backend server did not respond."
        return
    }
    ## return proxy result
    if { $result eq 1 }{
       if {$static::sb_debug > 1} {log local0. "Is the connection authorized: $result"}
    } else {
       if {$static::sb_debug > 1} {log local0. "Connection is not authorized: $result"}
       HTTP::respond 400 content '{"status":"Not_Authorized"}'  "Content-Type" "application/json"
    }
}

