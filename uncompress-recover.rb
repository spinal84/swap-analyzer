#!/usr/bin/ruby
$:.unshift(File.dirname(__FILE__))
require 'lib/swap'

class Swap
	def cmp_indexes
		return @cmp_indexes if @cmp_indexes
		i = 1
		@cmp_indexes, @cmp_sizes = [], []
		while i < entries.size
			cmp_indexes << i
			cmp_len = read_cmp_len(entries[i])
			break if cmp_len == 0 or cmp_len > LZO_CMP_WORST
			cmp_sizes << cmp_len
			i += div_round_up(cmp_sizes[-1] + LZO_HEADER, PAGE_SIZE)
		end
		@cmp_indexes
	end
end

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
	percent = (i + 1) * 100.0 / swap.cmp_chunks
	print "[#{percent.round(1)}%] #{i + 1}/#{swap.cmp_chunks}\r"
	(unc = swap.unc_chunk(i)) rescue next
	cmp_len += swap.cmp_sizes[i]
	unc_len += unc.length
	out_file.write(unc)
end

puts "Compressed size:   #{cmp_len}"
puts "Uncompressed size: #{unc_len}"
