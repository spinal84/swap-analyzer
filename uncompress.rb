#!/usr/bin/ruby
$:.unshift(File.dirname(__FILE__))
require 'lib/swap'

abort "#$0 <swap> [<uncomp_swap>]" unless [1, 2].include?(ARGV.size)
swap = Swap.new(ARGV[0]) rescue abort($!.to_s)

swap.dump_header
swap.dump_swsusp_info
#swap.dump_lzo_constants

exit if ARGV.size == 1

out_file = ARGV[1]
abort "File '#{out_file}' exists! Exiting..." if File.exists?(out_file)

out_file = File.open(out_file, 'w')
at_exit { out_file.close }

puts "\nUncompressing swap..."
cmp_len, unc_len = 0, 0
(0...swap.cmp_chunks).each do |i|
	print "[#{((i + 1) * 100 / swap.cmp_chunks.to_f).round}%] #{i + 1}/#{swap.cmp_chunks}\r"
	cmp_len += swap.cmp_sizes[i]
	unc = swap.unc_chunk(i)
	unc_len += unc.length
	out_file.write(unc)
end

puts "Compressed size:   #{cmp_len}"
puts "Uncompressed size: #{unc_len}"
