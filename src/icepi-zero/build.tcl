# build.tcl — headless Lattice Diamond build

set proj "snestang.ldf"

prj_project open $proj

prj_run Export -impl impl -forceAll -task Bitgen

puts "=== Saving and closing ==="
# prj_project save
prj_project close

puts "=== Done ==="
puts "You can now e.g. run 'openFPGALoader -b icepi-zero impl/snestang_impl.bit'"
