require 'lib/lzo'

class Swap
	attr_reader :sectors

	def initialize(path)
		raise "File not found: #{path}" unless File.exists?(path)
		raise "Can't read file: #{path}" unless File.readable?(path)
		@swap = File.open(path, 'rb')
		if File.blockdev? path
			tmp = [0].pack("Q")
			@swap.ioctl(0x80081272, tmp)
			swap_size = tmp.unpack('Q').first
		else
			swap_size = File.size(path)
		end
		@sectors = swap_size / PAGE_SIZE
		at_exit { @swap.close }
	end

	PAGE_SIZE=4096
	SF_PLATFORM_MODE = 1
	SF_NOCOMPRESS_MODE = 2
	SF_CRC32_MODE = 4

	# struct swsusp_header {
	#     char reserved[PAGE_SIZE - 20 - sizeof(sector_t) - sizeof(int) -
	#                   sizeof(u32)];
	#     u32 crc32;
	#     sector_t image;
	#     unsigned int flags; /* Flags to pass to the "boot" kernel */
	#     char    orig_sig[10];
	#     char    sig[10];
	# };
	SwsuspHeader = Struct.new(:reserved, :crc32, :image, :flags, :orig_sig, :sig)

	def header
		return @header if @header
		# Read swsusp_header. Its description from kernel/power/swap.c:

		reserved_size = PAGE_SIZE - 20 - 8 - 4 - 4
		sector = read_sector(0)
		@header = SwsuspHeader.new(*sector.unpack("a#{reserved_size}LQLZ10Z10"))
		@header.reserved = "..."

		@header
	end

	def dump_header
		w = 20
		puts "************"
		puts "** HEADER **"
		puts "************"
		puts "%#{w}s" % "sectors: " + "#@sectors"
		puts "%#{w}s" % "orig_sig: " + "'#{header.orig_sig}'"
		puts "%#{w}s" % "sig: " + "'#{header.sig}'"
		puts "%#{w}s" % "crc32: " + "#{header.crc32.to_s(16)}"
		puts "%#{w}s" % "image: " + "#{header.image}"
		puts "%#{w}s" % "SF_PLATFORM_MODE: " + "#{header.flags & SF_PLATFORM_MODE != 0}"
		puts "%#{w}s" % "SF_NOCOMPRESS_MODE: " + "#{header.flags & SF_NOCOMPRESS_MODE != 0}"
		puts "%#{w}s" % "SF_CRC32_MODE: " + "#{header.flags & SF_CRC32_MODE != 0}"
	end

	# #define MAP_PAGE_ENTRIES    (PAGE_SIZE / sizeof(sector_t) - 1)
	MAP_PAGE_ENTRIES = (PAGE_SIZE / 8 - 1)

	# The image sector points to this struct:
	# struct swap_map_page {
	#     sector_t entries[MAP_PAGE_ENTRIES];
	#     sector_t next_swap;
	# };
	SwapMapPage = Struct.new(:entries, :next_swap)

	def map_page_list
		return @map_page_list if @map_page_list
		@map_page_list = Array.new

		s = header.image

		while s != 0
			sector = read_sector(s)
			unpacked = sector.unpack("Q#{MAP_PAGE_ENTRIES}Q")
			@map_page_list << SwapMapPage.new(unpacked[0...MAP_PAGE_ENTRIES], unpacked[-1])
			s = @map_page_list[-1].next_swap
		end

		@map_page_list
	rescue
		warn "Warning: MapPageList is out of bounds! (#{@map_page_list[-1].next_swap * PAGE_SIZE}).\n" \
			"Warning: Pages parsed: #{@map_page_list.size * MAP_PAGE_ENTRIES}. " \
			"Last read: #{@map_page_list[-2].next_swap * PAGE_SIZE}." rescue nil
		@map_page_list
	end

	def entries
		return @entries if @entries

		@entries = Array.new
		map_page_list.each do |map_page|
			@entries.concat(map_page.entries)
		end

		@entries.pop while @entries.last.zero?

		@entries
	end

	def swaps
		return @swaps if @swaps

		@swaps = [header.image]
		map_page_list.each do |map_page|
			@swaps << map_page.next_swap
		end

		@swaps.pop if @swaps.last == 0

		@swaps
	end

	# #define __NEW_UTS_LEN 64
	#
	# struct new_utsname {
	# 	char sysname[__NEW_UTS_LEN + 1];
	# 	char nodename[__NEW_UTS_LEN + 1];
	# 	char release[__NEW_UTS_LEN + 1];
	# 	char version[__NEW_UTS_LEN + 1];
	# 	char machine[__NEW_UTS_LEN + 1];
	# 	char domainname[__NEW_UTS_LEN + 1];
	# };
	#
	# struct swsusp_info {
	# 	struct new_utsname      uts;
	# 	u32                     version_code;
	# 	unsigned long           num_physpages;
	# 	int                     cpus;
	# 	unsigned long           image_pages;
	# 	unsigned long           pages;
	# 	unsigned long           size;
	# };
	
	NEW_UTS_LEN = 64
	REAL_UTS_LEN = NEW_UTS_LEN + 1 + 2 - (NEW_UTS_LEN + 1) % 2
	NewUTSName = Struct.new(:sysname, :nodename, :release, :version, :machine, :domainname)
	SwsuspInfo = Struct.new(:uts, :version_code, :num_physpages, :cpus, :image_pages, :pages, :size)

	def swsusp_info
		return @swsusp_info if @swsusp_info

		sector = read_sector(map_page_list[0].entries.first)
		unpacked = sector.unpack("Z#{REAL_UTS_LEN}" * 6 + "LQqQQQ")

		uts = NewUTSName.new(*unpacked[0...6])
		@swsusp_info = SwsuspInfo.new(uts, *unpacked[6..-1])

		@swsusp_info
	end

	def dump_swsusp_info
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

	# /* We need to remember how much compressed data we need to read. */
	# #define LZO_HEADER  sizeof(size_t)
	LZO_HEADER = 8

	# /* Number of pages/bytes we'll compress at one time. */
	# #define LZO_UNC_PAGES   32
	# #define LZO_UNC_SIZE    (LZO_UNC_PAGES * PAGE_SIZE)
	LZO_UNC_PAGES = 32
	LZO_UNC_SIZE = LZO_UNC_PAGES * PAGE_SIZE

	# /* Number of pages/bytes we need for compressed data (worst case). */
	# #define LZO_CMP_PAGES   DIV_ROUND_UP(lzo1x_worst_compress(LZO_UNC_SIZE) + \
	#                          LZO_HEADER, PAGE_SIZE)
	# #define LZO_CMP_SIZE    (LZO_CMP_PAGES * PAGE_SIZE)
	# #define DIV_ROUND_UP(n, d)  (((n) + (d) - 1) / (d))
	# #define lzo1x_worst_compress(x) ((x) + ((x) / 16) + 64 + 3)
	LZO_CMP_WORST = LZO_UNC_SIZE + LZO_UNC_SIZE / 16 + 64 + 3
	LZO_CMP_PAGES = (LZO_CMP_WORST + LZO_HEADER + PAGE_SIZE - 1) / PAGE_SIZE
	LZO_CMP_SIZE = LZO_CMP_PAGES * PAGE_SIZE

	def dump_lzo_constants
		puts "*******************"
		puts "** LZO constants **"
		puts "*******************"
		puts "LZO_HEADER    = #{LZO_HEADER}"
		puts "LZO_UNC_PAGES = #{LZO_UNC_PAGES}"
		puts "LZO_UNC_SIZE  = #{LZO_UNC_SIZE}"
		puts "LZO_CMP_WORST = #{LZO_CMP_WORST}"
		puts "LZO_CMP_PAGES = #{LZO_CMP_PAGES}"
		puts "LZO_CMP_SIZE  = #{LZO_CMP_SIZE}"
	end

	def cmp_chunk(n)
		i = cmp_indexes[n]
		cmp_len, compressed = read_sector(entries[i]).unpack("Qa*")
		if cmp_len == 0 or cmp_len > LZO_CMP_WORST
			raise "Invalid LZO compressed length"
		end
		need = div_round_up(cmp_len + LZO_HEADER, PAGE_SIZE) - 1
		need.times do
			i += 1
			compressed << read_sector(entries[i])
		end
		compressed[0...cmp_len]
	end

	def unc_chunk(n)
		cmp = cmp_chunk(n)
		unc = LZO::decompress(cmp)
		unc_len = unc.length
		if unc_len == 0 or unc_len > LZO_UNC_SIZE or unc_len & (PAGE_SIZE - 1) != 0
			raise "Invalid LZO uncompressed length"
		end
		unc
	end

	def cmp_chunks
		cmp_indexes.length
	end

	def cmp_sizes
		return @cmp_sizes if @cmp_sizes
		cmp_indexes
		@cmp_sizes
	end

	def read_cmp_len(n)
		@swap.seek(n * PAGE_SIZE)
		@swap.read(LZO_HEADER).unpack('Q')[0]
	end

	private
	def read_sector(n)
		@swap.seek(n * PAGE_SIZE)
		@swap.read(PAGE_SIZE)
	end

	# #define DIV_ROUND_UP(n, d)  (((n) + (d) - 1) / (d))
	def div_round_up(n, d)
		(n + d - 1) / d
	end

	def cmp_indexes
		return @cmp_indexes if @cmp_indexes
		i = 1
		@cmp_indexes, @cmp_sizes = [], []
		while i < entries.size
			cmp_indexes << i
			cmp_len = read_cmp_len(entries[i])
			if cmp_len == 0 or cmp_len > LZO_CMP_WORST
				raise "Invalid LZO compressed length: #{cmp_len}"
			end
			cmp_sizes << cmp_len
			i += div_round_up(cmp_sizes[-1] + LZO_HEADER, PAGE_SIZE)
		end
		@cmp_indexes
	end
end
