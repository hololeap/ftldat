require 'fileutils'
require 'find'

class FTLDat::DatFile < File
  include Enumerable

  Metadata = Struct.new :filename, :size, :offset do
    def data_offset
      offset + 8 + filename.size
    end
  end

  attr_reader :metadata
  def initialize(file)
    @index_size = 2048
    super(file, File.exists?(file) ? 'r' : 'w')
  end

  def each
    @metadata ||= get_metadata
    return to_enum unless block_given?
    @metadata.each do |m|
      seek m.data_offset
      yield m, read(m.size)
    end
  end

  def unpack(path)
    if File.exists? path and not File.directory? path
      raise "#{path} already exists (and isn't a directory)"
    end

    each do |m, data|
      file_path = File.join(path, m.filename)
      FileUtils.mkpath File.dirname(file_path)
      File.write(file_path, data)
    end
  end

  def pack(*paths)
    # path is actually File#path
    tmp_file = File.join('/tmp', File.basename(path) + '.bak')
    FileUtils.copy(path, tmp_file)
    metadata = []

    begin 
      reopen(path, 'w+')
      write_long(@index_size)
      @index_size.times { write_long(0) }

      Find.find(*paths) do |p|
        next if File.directory? p
        data = File.read(p)
        metadata << Metadata.new(p, data.size, pos)

        [data.size, p.size].each {|i| write_long(i) }
        [p, data].each {|s| write(s) }
      end

      seek 4
      metadata.each {|m| write_long(m.offset) }

      @metadata = metadata
      FileUtils.remove(tmp_file)

    rescue Exception => e
      FileUtils.move(tmp_file, path)
      raise e
    ensure
      reopen(path, 'r')
    end
      
  end 


  private

  def get_metadata
    index = []
   
    rewind
    @index_size = read_long
    @index_size.times do
      offset = read_long
      index << p(offset) unless offset == 0
    end

    index.map do |offset|
      seek offset
      size, filename_size = read_long(2)
      filename = read(filename_size)
      Metadata.new filename, size, offset 
    end
  end

  def read_long(times = 1)
    doit = -> { read(4).unpack('L<').first }
    times > 1 ? Array.new(times) { doit.call } : doit.call
  end

  def write_long(long)
    write([long].pack('L<'))
  end

end
