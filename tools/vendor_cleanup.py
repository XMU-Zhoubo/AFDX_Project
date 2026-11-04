"""Verified C42S cleanup function, no controller import."""
def cleanup(top):
 return [f'set before [examine -radix unsigned -noshowbase /{top}/cycles]','set before_time [now]',
 'if {![auto_load ::SVStructure::Restore]} {quit -force -code 83}',
 'if {[llength [vsim_kernel info commands ::SVStructure::Restore]] != 1} {',
 ' set vendor_entry $::auto_index(::SVStructure::Restore)',
 ' if {[lindex $vendor_entry 0] ne "source"} {quit -force -code 83}',
 ' set vendor_source [lindex $vendor_entry 1]',
 ' set vendor_copy [file normalize [file join [pwd] inputs host SVStructure-original.tc_]]',
 ' file mkdir [file dirname $vendor_copy]',
 ' file copy -force $vendor_source $vendor_copy',
 ' set input [open $vendor_source rb];set original_bytes [read $input];close $input',
 ' set input [open $vendor_copy rb];set copied_bytes [read $input];close $input',
 ' if {$original_bytes ne $copied_bytes} {quit -force -code 83}',
 ' puts "C42S_ORIGINAL_VENDOR_BYTE_COPY bytes=[string length $original_bytes] source=$vendor_source destination=$vendor_copy"',
 ' vsim_kernel source $vendor_copy',
 '}',
 'if {[llength [vsim_kernel info commands ::SVStructure::Restore]] != 1} {quit -force -code 83}',
 'update idletasks','update',f'if {{[examine -radix unsigned -noshowbase /{top}/cycles] != $before || [now] ne $before_time}} {{quit -force -code 83}}']
