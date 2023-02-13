#!/usr/bin/ruby
$:.unshift(File.dirname(__FILE__))
require 'lib/swap'

class Swap
	def unc_straight(i)
		cmp_len, compressed = read_sector(i).unpack("Qa*")
		return nil if cmp_len == 0 or cmp_len > LZO_CMP_WORST
		need = div_round_up(cmp_len + LZO_HEADER, PAGE_SIZE) - 1
		need.times do
			i += 1
			compressed << read_sector(i)
		end
		cmp = compressed[0...cmp_len]
		unc = LZO::decompress(cmp)
		unc_len = unc.length
		return nil if unc_len == 0 or unc_len > LZO_UNC_SIZE or unc_len & (PAGE_SIZE - 1) != 0
		unc
	rescue
		nil
	end
end

abort "#$0 <swap> [<uncomp_swap>]" unless [1, 2].include?(ARGV.size)
swap = Swap.new(ARGV[0]) rescue abort($!.to_s)

swap.dump_header
swap.dump_swsusp_info
swap.dump_lzo_constants

exit if ARGV.size == 1

out_file = ARGV[1]
abort "File '#{out_file}' exists! Exiting..." if File.exists?(out_file)

out_file = File.open(out_file, 'w')
at_exit { out_file.close }

puts "\nUncompressing swap..."
cmp_len, unc_len = 0, 0

(0...swap.sectors).each do |i|
	print "[#{((i + 1) * 100.00 / swap.sectors).round}%] #{i + 1}/#{swap.sectors} cmp/unc: #{cmp_len}/#{unc_len}\r"
	unc = swap.unc_straight(i)
	if unc
		cmp_len += swap.read_cmp_len(i)
		unc_len += unc.length
		out_file.write(unc)
	end
end

puts " " * 80 + "\r"
puts "Compressed size:   #{cmp_len}"
puts "Uncompressed size: #{unc_len}"
