#!/usr/bin/ruby
$:.unshift(File.dirname(__FILE__))
require 'lib/swap'

class Swap
	def swsusp_info_similar(i1, i2)
		i1.uts == i2.uts and i1.version_code == i2.version_code and
			i1.num_physpages == i2.num_physpages and i1.cpus == i2.cpus
	end

#	# You may want to enter your values by hand here
#	def swsusp_info
#		return @swsusp_info if @swsusp_info
#		uts = NewUTSName.new(*([''] * 6))
#		return @swsusp_info = SwsuspInfo.new(uts, 0, 3137037, 0)
#	end

	def swsusp_info_from_sector(i)
		sector = read_sector(i)
		unpacked = sector.unpack("Z#{REAL_UTS_LEN}" * 6 + "LQqQQQ")

		uts = NewUTSName.new(*unpacked[0...6])
		SwsuspInfo.new(uts, *unpacked[6..-1])
	end

	def dump_swsusp_info_from_sector(i)
		swsusp_info = swsusp_info_from_sector(i)
		w = 16
		puts "*****************"
		puts "** swsusp_info **"
		puts "*****************"
		if swsusp_info.uts.to_a.find {|f| ! f.empty? }
			puts "%#{w}s" % "uts.sysname: " + "#{swsusp_info.uts.sysname}"
			puts "%#{w}s" % "uts.nodename: " + "#{swsusp_info.uts.nodename}"
			puts "%#{w}s" % "uts.release: " + "#{swsusp_info.uts.release}"
			puts "%#{w}s" % "uts.version: " + "#{swsusp_info.uts.version}"
			puts "%#{w}s" % "uts.machine: " + "#{swsusp_info.uts.machine}"
			puts "%#{w}s" % "uts.domainname: " + "#{swsusp_info.uts.domainname}"
		end
		puts "%#{w}s" % "version_code: " + "#{swsusp_info.version_code}"
		puts "%#{w}s" % "num_physpages: " + "#{swsusp_info.num_physpages}"
		puts "%#{w}s" % "cpus: " + "#{swsusp_info.cpus}"
		puts "%#{w}s" % "image_pages: " + "#{swsusp_info.image_pages}"
		puts "%#{w}s" % "pages: " + "#{swsusp_info.pages}"
		puts "%#{w}s" % "size: " + "#{swsusp_info.size}"
	end
end

abort "#$0 <swap>" unless ARGV.size == 1
swap = Swap.new(ARGV[0]) rescue abort($!.to_s)

swap.dump_header
swap.dump_swsusp_info

possible_swsusp_info = []
puts "\nLooking for possible swsusp_info sectors..."
(1...swap.sectors).each do |i|
	percent = (i + 1) * 100.0 / swap.sectors
	print "[#{percent.round(1)}] #{i + 1}/#{swap.sectors}; found: #{possible_swsusp_info.length}\r"
	swap.swsusp_info_similar(swap.swsusp_info, swap.swsusp_info_from_sector(i)) and possible_swsusp_info << i
end 
print " " * 80 + "\r"

puts possible_swsusp_info.join(", ")
