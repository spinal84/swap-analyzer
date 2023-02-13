#!/usr/bin/ruby
$:.unshift(File.dirname(__FILE__))
require 'lib/swap'

class Swap
	def map_page_possible(i)
		return nil if i.zero?
		sector = read_sector(i)
		unpacked = sector.unpack("Q#{MAP_PAGE_ENTRIES}Q")
		map_page = SwapMapPage.new(unpacked[0...MAP_PAGE_ENTRIES], unpacked[-1])
		return nil if map_page.entries.find {|e| e > @sectors }
		return nil if map_page.next_swap > @sectors
		return nil if map_page.entries.last.zero? and !map_page.next_swap.zero?
		map_page.entries.pop while (map_page.entries.last.zero? rescue nil)
		return nil if map_page.entries.empty?
		return nil if map_page.entries.include?(0)
		return nil if map_page.entries == [1]
		map_page.entries.uniq.length == map_page.entries.length ? map_page : nil
	end
end

abort "#$0 <swap> [<uncomp_swap>]" unless [1, 2].include?(ARGV.size)
swap = Swap.new(ARGV[0]) rescue abort($!.to_s)

swap.dump_header
swap.dump_swsusp_info

marshal_file = '/dev/shm/__possible_map_pages__'
if File.exists? marshal_file
	load_ary = File.open(marshal_file) {|dumpfile| Marshal.load dumpfile.read }
	possible_map_pages = load_ary[1] if load_ary[0] == File.expand_path(ARGV[0])
	load_ary.clear
end

puts "\nLooking for possible swap_map_pages..."
unless possible_map_pages
	possible_map_pages = []
	(1...swap.sectors).each do |i|
		percent = (i + 1) * 100.0 / swap.sectors
		print "[#{percent.round(1)}%] #{i + 1}/#{swap.sectors}; found: #{possible_map_pages.length}\r"

		swap.map_page_possible(i) and possible_map_pages << i
	end

	File.open(marshal_file, 'w') {|file| Marshal.dump([File.expand_path(ARGV[0]), possible_map_pages], file) }

	print " " * 80 + "\r"
end

puts "Making map_pages_lists..."
j = 0
map_pages_lists = possible_map_pages.map do |i|
	j += 1
	percent = (j) * 100.0 / possible_map_pages.length
	print "[#{percent.round(1)}%] #{j}/#{possible_map_pages.length}\r"

	a = [i]
	map_page = swap.map_page_possible(i)
	loop do
		next_swap = map_page.next_swap
		map_page = swap.map_page_possible(next_swap)
		break unless map_page
		a << next_swap
	end
	a
end

print " " * 80 + "\r"
puts "Excluding duplicates..."
map_pages_lists2 = map_pages_lists.dup

map_pages_lists2.each_with_index do |list, i|
	# Exclude from map_pages_lists those lists that are included in other
	percent = (i + 1) * 100.0 / map_pages_lists2.length
	print "[#{percent.round(1)}%] #{i + 1}/#{possible_map_pages.length}\r"

	found = map_pages_lists.find do |l|
		next if l == list
		l.include?(list[0])
	end

	map_pages_lists.delete(list) if found
end

print " " * 80 + "\r"
puts "Sorting..."

map_pages_lists.sort! {|a, b| b.length <=> a.length }
map_pages_lists2.clear

map_pages_lists.each do |l|
	if l.length > 1
		p l
		next
	end
	#puts "#{l.inspect}, next_swap = #{swap.map_page_possible(l[0]).next_swap}"
	puts "#{l.inspect}, #{swap.map_page_possible(l[0]).inspect}"
end
