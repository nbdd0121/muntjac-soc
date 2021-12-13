if { [get_property needs_refresh [get_runs synth_1]] } {
    reset_runs synth_1
}

if { [get_property progress [get_runs synth_1]] != "100%"} {
  launch_runs synth_1
  wait_on_run synth_1
  puts "Synthesis completed"
} else {
  puts "Synthesis already complete"
}

if { [get_property progress [get_runs synth_1]] != "100%"} {
   puts "ERROR: Synthesis failed."
   exit 1
}

if { [get_property needs_refresh [get_runs impl_1]] } {
    reset_runs impl_1
}

if { [get_property progress [get_runs impl_1]] != "100%"} {
  launch_runs impl_1 -to_step write_bitstream
  wait_on_run impl_1
  puts "Bitstream generation completed"
} else {
  puts "Bitstream generation already complete"
}

if { [get_property progress [get_runs impl_1]] != "100%"} {
   puts "ERROR: Implementation and bitstream generation step failed."
   exit 1
}

set vivadoDefaultBitstreamFile [ get_property DIRECTORY [current_run] ]/[ get_property top [current_fileset] ].bit
file copy -force $vivadoDefaultBitstreamFile [pwd]/[current_project].bit
