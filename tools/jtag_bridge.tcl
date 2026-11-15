# Interrupt Debugger USER1/USER2 access through the installed Xilinx ISE CSE API.
# This file is project code; it does not redistribute Xilinx's implementation.
namespace eval irqscope {
    variable handle ""
    variable target_opened 0
    variable cable_locked 0
    variable device -1
    variable last_message ""
    variable cable_port USB2
    variable frequency 1500000
    variable samples 8192
    variable active ""
    variable cancelled 0
    variable diagnostic_dir ""
    variable diagnostic_root ""
    variable reset_on_error 1
    variable read_confirmed 0
}

# ISE 14.7's xtclsh uses Tcl 8.4, which has no clock milliseconds, dict,
# lreverse or expression membership operators. Keep the bridge compatible.
proc irqscope::milliseconds {} {return [clock clicks -milliseconds]}
proc irqscope::reverse_list {values} {
    set result {}
    for {set index [expr {[llength $values]-1}]} {$index>=0} {incr index -1} {
        lappend result [lindex $values $index]
    }
    return $result
}
proc irqscope::write_packet {destination data} {
    if {[file exists $destination]} {error "Output already exists: $destination"}
    set stream [::open $destination {WRONLY CREAT EXCL}]
    set failed [catch {
        fconfigure $stream -translation binary
        puts -nonewline $stream $data
    } problem]
    ::close $stream
    if {$failed} {error $problem}
}

proc irqscope::message {session flags text} {
    variable last_message
    append last_message $text
    puts -nonewline stderr $text
}
proc irqscope::checked {args} {
    variable last_message
    set last_message ""
    if {[catch {uplevel 1 $args} result]} {
        if {$last_message eq ""} {set last_message "JTAG operation failed: [lindex $args 1]"}
        error [string trim $last_message]
    }
    return $result
}
proc irqscope::open {} {
    variable handle
    variable device
    variable target_opened
    variable cable_locked
    variable cable_port
    variable frequency
    if {[info exists ::env(IRQSCOPE_TCK_HZ)]} {
        if {$::env(IRQSCOPE_TCK_HZ)!=750000 && $::env(IRQSCOPE_TCK_HZ)!=1500000} {
            error "Use 750000 or 1500000 Hz TCK"
        }
        set frequency $::env(IRQSCOPE_TCK_HZ)
    }
    if {![info exists ::env(XILINX)]} {set ::env(XILINX) /opt/Xilinx/14.7/ISE_DS/ISE}
    if {[llength [info commands ::chipscope::csejtag_session]] == 0} {
        uplevel #0 [list source $::env(XILINX)/cse/tcl/csejtag.tcl]
    }
    set handle [checked ::chipscope::csejtag_session create ::irqscope::message {}]
    if {[catch {checked ::chipscope::csejtag_target open $handle $::CSEJTAG_TARGET_PLATFORMUSB 0 \
        [list port=$cable_port frequency=$frequency]}]} {
        error "Could not connect to the Xilinx USB-JTAG cable. Check board power, USB passthrough and cable ownership."
    }
    set target_opened 1
    if {[checked ::chipscope::csejtag_target lock $handle 5000] != $::CSEJTAG_LOCKED_ME} {
        error "The JTAG cable is in use. Close iMPACT or ChipScope and try again."
    }
    set cable_locked 1
    checked ::chipscope::csejtag_tap autodetect_chain $handle $::CSEJTAG_SCAN_DEFAULT
    set count [checked ::chipscope::csejtag_tap get_device_count $handle]
    set matches {}
    for {set index 0} {$index < $count} {incr index} {
        set id [checked ::chipscope::csejtag_tap get_device_idcode $handle $index]
        set name [checked ::chipscope::csejtag_db get_device_name_for_idcode $handle $id]
        if {[string match -nocase *xc3s1600e* $name]} {lappend matches $index}
    }
    if {[llength $matches] != 1} {error "Expected exactly one XC3S1600E in the JTAG chain"}
    set device [lindex $matches 0]
    # Explicitly bypass the PROM/CPLD and any other devices; never program them.
    for {set index 0} {$index < $count} {incr index} {
        set id [checked ::chipscope::csejtag_tap get_device_idcode $handle $index]
        set bits [checked ::chipscope::csejtag_db get_irlength_for_idcode $handle $id]
        if {$bits < 1 || $bits > 32} {error "Unknown or unsupported JTAG instruction length"}
        checked ::chipscope::csejtag_tap shift_device_ir $handle $index \
            $::CSEJTAG_SHIFT_WRITE $::CSEJTAG_RUN_TEST_IDLE 0 $bits [format %X [expr {(1<<$bits)-1}]]
    }
}
proc irqscope::close {} {
    variable handle
    variable target_opened
    variable cable_locked
    if {$handle ne ""} {
        if {$cable_locked} {catch {::chipscope::csejtag_target unlock $handle}}
        if {$target_opened} {catch {::chipscope::csejtag_target close $handle}}
        catch {::chipscope::csejtag_session destroy $handle}
        set handle ""
        set target_opened 0
        set cable_locked 0
    }
}
proc irqscope::select {instruction} {
    variable handle
    variable device
    checked ::chipscope::csejtag_tap shift_device_ir $handle $device \
        $::CSEJTAG_SHIFT_WRITE $::CSEJTAG_RUN_TEST_IDLE 0 6 [format %02X $instruction]
}
proc irqscope::control {value} {
    variable handle
    variable device
    variable diagnostic_dir
    set hex [checked ::chipscope::csejtag_tap shift_device_dr $handle $device \
        $::CSEJTAG_SHIFT_READWRITE $::CSEJTAG_RUN_TEST_IDLE 0 32 [format %08X $value]]
    if {$diagnostic_dir ne ""} {
        file mkdir $diagnostic_dir
        set log [::open [file join $diagnostic_dir control.log] a]
        puts $log [format "tdi=%08X tdo=%s" $value $hex]
        ::close $log
    }
    if {![scan $hex %x word]} {error "Invalid JTAG status response"}
    return $word
}
proc irqscope::identity {} {
    select 2
    for {set attempt 0} {$attempt < 6} {incr attempt} {
        set value [control 0]
        if {(($value>>16)&65535)==0x4953 && (($value>>12)&15)==3} {return $value}
    }
    error "Interrupt Debugger JTAG v3 was not found. Program the matching JTAG design and reset the board."
}
# Extended USER1 is backwards compatible with 32-bit command/status scans.
# It is read only when capability bit 4 and frozen bit 1 are set. The diagnostic
# source is then stable, not an unsynchronized live multi-bit bus.
proc irqscope::read_diagnostics {} {
    variable handle
    variable device
    set hex [checked ::chipscope::csejtag_tap shift_device_dr $handle $device \
        $::CSEJTAG_SHIFT_READWRITE $::CSEJTAG_RUN_TEST_IDLE 0 128 0]
    if {![regexp {^[0-9a-fA-F]{1,32}$} $hex]} {error "Invalid extended USER1 response"}
    set hex "[string repeat 0 [expr {32-[string length $hex]}]]$hex"
    if {![string equal -nocase [string range $hex 16 19] d149]} {
        error "Extended USER1 diagnostic signature mismatch"
    }
    return [string tolower $hex]
}
proc irqscope::command {letter} {
    set previous [expr {([control 0]>>8)&1}]
    scan $letter %c code
    control $code
    set deadline [expr {[milliseconds]+2000}]
    while {[milliseconds] < $deadline} {
        set status [control 0]
        if {(($status>>8)&1)!=$previous} {return $status}
        update
    }
    error "The FPGA did not acknowledge the command. Check clock/reset and the programmed image."
}

proc irqscope::crc16 {data} {
    binary scan $data c* bytes
    set crc 65535
    foreach byte $bytes {
        set crc [expr {$crc^(($byte&255)<<8)}]
        for {set bit 0} {$bit<8} {incr bit} {
            set crc [expr {(($crc&32768)!=0 ? (($crc<<1)^0x1021) : ($crc<<1))&65535}]
        }
    }
    return $crc
}
proc irqscope::le32 {data offset} {
    binary scan [string range $data $offset [expr {$offset+3}]] c* bytes
    set result 0
    set shift 0
    foreach byte $bytes {set result [expr {$result|(($byte&255)<<$shift)}]; incr shift 8}
    return $result
}
proc irqscope::valid_packet {data count} {
    if {[string length $data] != 18+4*$count || [string range $data 0 3] ne "IRQ2"} {return 0}
    if {[le32 $data 4]!=$count || [le32 $data 8]<1 || [le32 $data 8]>100000000} {return 0}
    if {[le32 $data 12]!=0 && [le32 $data 12]!=8} {return 0}
    binary scan [string range $data end-1 end] c* trailer
    set expected [expr {(([lindex $trailer 0]&255)<<8)|([lindex $trailer 1]&255)}]
    return [expr {[crc16 [string range $data 0 end-2]]==$expected}]
}
proc irqscope::decode_hex {hex count} {
    set hex [string map [list " " "" "\n" "" "\r" "" "\t" ""] $hex]
    regsub -nocase {^0x} $hex {} hex
    set length [expr {2*(18+4*$count)}]
    if {![regexp {^[0-9a-fA-F]+$} $hex] || [string length $hex]>$length} {error "Invalid JTAG scan data"}
    set hex "[string repeat 0 [expr {$length-[string length $hex]}]]$hex"
    set raw [binary format H* $hex]
    binary scan $raw c* bytes
    set variants [list $raw [binary format c* [reverse_list $bytes]]]
    set word_order {}
    for {set index 0} {$index<[llength $bytes]} {incr index 4} {
        set word_order [concat $word_order [reverse_list [lrange $bytes $index [expr {$index+3}]]]]
    }
    lappend variants [binary format c* $word_order]
    foreach candidate $variants {
        if {[valid_packet $candidate $count]} {return $candidate}
    }
    error "JTAG packet failed its header or FPGA-generated CRC check"
}
proc irqscope::capture_packet {scenario pattern} {
    variable reset_on_error
    switch -- $scenario {
        normal {set program N; set index 0}
        masked_ir1 {set program A; set index 1}
        masked {set program M; set index 2}
        missing_eoi {set program F; set index 3}
        default {error "Invalid capture request"}
    }
    if {$pattern ne "C" && $pattern ne "P"} {error "Invalid capture request"}
    set status [identity]
    if {($status&32)!=0} {
        set reset_on_error 0
        error "Board controls are enabled. Press NORTH and read the board capture, or turn SW3 off for GUI-generated requests."
    }
    command R
    command $program
    command $pattern
    set status [wait_frozen 5000]
    if {($status&64)!=0} {
        set reset_on_error 0
        error "A board Start replaced the GUI experiment; read the board capture instead"
    }
    if {(($status>>10)&3)!=$index || (($status>>9)&1)!=($pattern eq "P")} {
        error "The FPGA scenario/pattern does not match the request"
    }
    set status [command L]
    set status [wait_frozen 5000]
    if {($status&128)==0} {error "Readout lock was not established"}
    if {($status&64)!=0 || (($status>>10)&3)!=$index || (($status>>9)&1)!=($pattern eq "P")} {
        set reset_on_error 0
        error "Capture changed before readout lock; read the board capture instead"
    }
    set failed [catch {read_frozen_packet $status} data]
    set release_failed [catch {select 2; command U} release_problem]
    if {$failed} {error $data}
    if {$release_failed} {error $release_problem}
    return $data
}
proc irqscope::wait_frozen {timeout} {
    variable cancelled
    set deadline [expr {[milliseconds]+$timeout}]
    while {[milliseconds]<$deadline} {
        update
        if {$cancelled} {error "Capture cancelled"}
        set status [control 0]
        if {($status&2)!=0} {return $status}
        after 20
    }
    error "No frozen capture. In board mode, turn SW3 on, select SW1:SW0, and press NORTH."
}
proc irqscope::read_board_packet {{keep_lock 0}} {
    variable reset_on_error
    set reset_on_error 0
    identity
    set status [wait_frozen 60000]
    if {($status&64)==0} {error "This capture was started by the GUI, not the board Start button"}
    command L
    set status [wait_frozen 5000]
    if {($status&128)==0 || ($status&64)==0} {error "Board capture changed before readout lock"}
    set index [expr {($status>>10)&3}]
    set scenario [lindex {normal masked_ir1 masked missing_eoi} $index]
    set pattern [expr {($status&512)!=0 ? "P" : "C"}]
    set failed [catch {read_frozen_packet $status} data]
    set release_failed 0
    if {$failed || !$keep_lock} {set release_failed [catch {select 2; command U} release_problem]}
    if {$failed} {error $data}
    if {$release_failed} {error $release_problem}
    return [list $data $scenario $pattern]
}
proc irqscope::confirm_gui_read {} {
    variable read_confirmed
    variable cancelled
    set deadline [expr {[milliseconds]+5000}]
    while {[milliseconds]<$deadline} {
        update
        if {$read_confirmed} {
            select 2
            set status [control 0]
            if {($status&194)!=194} {error "Capture reset before read acknowledgement"}
            command D
            command U
            return
        }
        if {$cancelled} {error "Capture read was not confirmed"}
        after 10
    }
    error "GUI did not confirm the capture; ready state retained"
}
proc irqscope::read_frozen_packet {status} {
    variable handle
    variable device
    variable samples
    variable cancelled
    variable diagnostic_dir
    if {$diagnostic_dir ne ""} {
        file mkdir $diagnostic_dir
        set log [::open [file join $diagnostic_dir frozen-status.txt] w]
        puts $log [format %08X $status]
        ::close $log
        if {($status&16)!=0} {
            set log [::open [file join $diagnostic_dir extended-status.hex] w]
            set failed [catch {read_diagnostics} snapshot]
            if {!$failed} {puts $log $snapshot}
            ::close $log
            if {$failed} {error $snapshot}
        }
    }
    select 3
    set bits [expr {8*(18+4*$samples)}]
    set hex [checked ::chipscope::csejtag_tap shift_device_dr $handle $device \
        $::CSEJTAG_SHIFT_READ $::CSEJTAG_RUN_TEST_IDLE 0 $bits 0]
    if {$diagnostic_dir ne ""} {
        set log [::open [file join $diagnostic_dir raw-scan.hex] w]
        puts $log $hex
        ::close $log
    }
    update
    if {$cancelled} {error "Capture cancelled"}
    return [decode_hex $hex $samples]
}

proc irqscope::accept {channel ip port} {
    fconfigure $channel -translation binary -blocking 0 -buffering none
    fileevent $channel readable [list irqscope::request $channel]
}
proc irqscope::request {channel} {
    variable active
    variable cancelled
    variable diagnostic_dir
    variable diagnostic_root
    variable reset_on_error
    variable read_confirmed
    if {[catch {gets $channel line} length] || [eof $channel]} {
        if {$active eq $channel} {set cancelled 1}
        catch {::close $channel}
        return
    }
    if {$length<0} {return}
    if {$length>200} {catch {puts $channel "ERR Request too long"}; catch {::close $channel}; return}
    if {$active eq $channel} {
        if {$line eq "CANCEL"} {set cancelled 1}
        if {$line eq "RECEIVED"} {set read_confirmed 1}
        return
    }
    if {$active ne ""} {catch {puts $channel "ERR A JTAG request is already running"}; catch {::close $channel}; return}
    set fields [split [string trim $line]]
    if {$line ne "CLEAR" && $line ne "READ_BOARD" && ([llength $fields]!=3 || [lindex $fields 0] ne "CAPTURE")} {
        catch {puts $channel "ERR Expected CLEAR, READ_BOARD or CAPTURE scenario pattern"}; catch {::close $channel}; return
    }
    set active $channel
    set cancelled 0
    set reset_on_error 1
    set read_confirmed 0
    set previous_diagnostics $diagnostic_dir
    set failed [catch {
        if {$diagnostic_root ne ""} {
            set diagnostic_dir [file join $diagnostic_root [clock seconds]-[pid]-[clock clicks]]
            file mkdir $diagnostic_dir
            set log [::open [file join $diagnostic_dir request.txt] w]
            puts $log $line
            ::close $log
        }
        open
        set response OK
        if {$line eq "CLEAR"} {identity; command R; set data ""} \
        elseif {$line eq "READ_BOARD"} {
            set board [read_board_packet 1]
            set data [lindex $board 0]
            set response "OK BOARD [lindex $board 1] [lindex $board 2]"
        } \
        else {set data [capture_packet [lindex $fields 1] [lindex $fields 2]]}
        if {!$cancelled} {
            if {$diagnostic_dir ne "" && $data ne ""} {write_packet [file join $diagnostic_dir capture.bin] $data}
            puts -nonewline $channel "$response\n$data"; flush $channel
            if {$line eq "READ_BOARD"} {
                confirm_gui_read
                puts $channel "OK"
                flush $channel
            }
        }
    } problem]
    if {$failed} {
        catch {select 2; command U}
        if {$reset_on_error} {catch {select 2; command R}}
        set problem [string map [list "\n" " " "\r" " "] $problem]
        catch {puts $channel "ERR [string range $problem 0 400]"}
    }
    close
    catch {::close $channel}
    set active ""
    set diagnostic_dir $previous_diagnostics
}
proc irqscope::stdin_request {} {
    if {[eof stdin]} {set ::irqscope::forever 1; return}
    if {[gets stdin line]>=0 && $line eq "STOP"} {set ::irqscope::forever 1}
}
proc irqscope::main {argv} {
    variable cable_port
    variable frequency
    variable samples
    variable diagnostic_root
    set bind 127.0.0.1
    set port 9374
    foreach {option value} $argv {
        switch -- $option {
            --bind {set bind $value}
            --port {set port $value}
            --cable-port {set cable_port $value}
            --frequency {set frequency $value}
            --samples {set samples $value}
            --diagnostics-root {set diagnostic_root $value}
            default {error "Unknown option: $option"}
        }
    }
    if {$frequency!=750000 && $frequency!=1500000} {error "Use 750000 or 1500000 Hz TCK"}
    if {![string is integer -strict $samples] || $samples<1 || $samples>32768} {error "Invalid sample count"}
    set listener [socket -server irqscope::accept -myaddr $bind $port]
    set port [lindex [fconfigure $listener -sockname] end]
    puts "Interrupt Debugger JTAG bridge listening on $bind:$port (host-only network only)"
    puts "BRIDGE_READY_PORT=$port"
    flush stdout
    fconfigure stdin -blocking 0
    fileevent stdin readable irqscope::stdin_request
    vwait ::irqscope::forever
    fileevent stdin readable {}
    ::close $listener
}
if {![info exists ::irqscope_library_only]} {irqscope::main $argv}
