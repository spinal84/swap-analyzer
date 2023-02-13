module LZO
	INFILE = '/dev/shm/__swsusp2bin_lzo.in'
	OUTFILE = '/dev/shm/__swsusp2bin_lzo.out'
	LZO_COMPRESSOR = File.dirname(__FILE__) + '/../minilzo-2.10/compress'
	LZO_DECOMPRESSOR = File.dirname(__FILE__) + '/../minilzo-2.10/decompress'

	def self.decompress(s)
		file = File.open(INFILE, 'w')
		file.write(s)
		file.close
		system("#{LZO_DECOMPRESSOR} #{INFILE} #{OUTFILE} >/dev/null") || raise("Decompression failure")
		file = File.open(OUTFILE, 'rb')
		result = file.read
		file.close
		result
	ensure
		File.unlink(INFILE) rescue nil
		File.unlink(OUTFILE) rescue nil
	end

	def self.compress(s)
		file = File.open(INFILE, 'w')
		file.write(s)
		file.close
		system("#{LZO_COMPRESSOR} #{INFILE} #{OUTFILE}") || raise("Compression failure")
		file = File.open(OUTFILE, 'rb')
		result = file.read
		file.close
		result
	ensure
		File.unlink(INFILE) rescue nil
		File.unlink(OUTFILE) rescue nil
	end
end
