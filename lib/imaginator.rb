require 'digest'
require 'fileutils'
require 'thread'
require 'monitor'
require 'drb'

class Imaginator
  VERSION = '0.1.4'

  class LaTeX
    def initialize(opts = {})
      @opts = {
        :convert_opts => '-trim -density 120',
        :format          => 'png',
        :debug           => false
      }
      @opts[:blacklist] = %w{
        include def command loop repeat open toks output input
        catcode name \\every \\errhelp \\errorstopmode \\scrollmode
        \\nonstopmode \\batchmode \\read \\write csname \\newhelp
        \\uppercase \\lowercase \\relax \\aftergroup \\afterassignment
        \\expandafter \\noexpand \\special $$
      }
      @opts.update(opts)
    end

    def format
      @opts[:format]
    end

    def render(code, file)
      begin
        temp_dir = create_temp_dir(file)
        latex2dvi(temp_dir, code)
        dvi2ps(temp_dir)
        ps2image(temp_dir, file)
      rescue
        FileUtils.rm_rf(temp_dir) if !@opts[:debug]
      else
        FileUtils.rm_rf(temp_dir)
      end
    end

    def process(code)
      errors = @opts[:blacklist].select { |cmd| code.include?(cmd) }
      errors.empty? || raise(ArgumentError.new("Invalid LaTeX commands #{errors.join(', ')}"))
      code.strip
    end

    private

    def template(code)
      <<END # {{{
\\documentclass{minimal}
\\newcommand\\use[2][]{\\IfFileExists{#2.sty}{\\usepackage[#1]{#2}}{}}
\\use[utf8]{inputenc}
\\use{amsmath}
\\use{amsfonts}
\\use{amssymb}
\\use{mathrsfs}
\\use{esdiff}
\\use{cancel}
\\use[dvips,usenames]{color}
\\use{nicefrac}
\\use[fraction=nice]{siunitx}
\\use{mathpazo}
\\begin{document}
$$
#{code}
$$
\\end{document}
END
      # }}}
    end

    def create_temp_dir(file)
      temp_dir = file + '-tmp'
      FileUtils.mkdir_p(temp_dir)
      temp_dir
    end

    def sh(cmd, args)
      `#{cmd} #{args} 2>&1 > /dev/null`
      raise RuntimeError.new("Execution of #{cmd} failed with status #{$?}") if $? != 0
    end

    def latex2dvi(dir, code)
      tex_file = File.join(dir, 'code.tex')
      File.open(tex_file, 'w') {|f| f.write(template(code)) }
      sh('latex', "--interaction=nonstopmode --output-directory=#{dir} #{tex_file}")
    end

    def dvi2ps(dir)
      file = File.join(dir, 'code')
      sh('dvips', "-E #{file}.dvi -o #{file}.ps")
    end

    def ps2image(dir, file)
      ps_file = File.join(dir, 'code.ps')
      sh('convert', "#{@opts[:convert_opts]} #{ps_file} #{file}")
    end
  end

  class Graphviz
    def initialize(opts = {})
      @opts = {
        :format => 'png',
        :cmd    => 'dot'
      }
      @opts.update(opts)
    end

    def format
      @opts[:format]
    end

    def render(code, file)
      IO.popen(@opts[:cmd] + " -T #{@opts[:format]} -o #{file}", 'w') {|io|
        io.write(code)
        io.close
      }
    end

    def process(code)
      code.strip
    end
  end

  @uri = nil
  @dir = nil

  class<< self
    attr_accessor :uri, :dir

    def get
      raise(ArgumentError, "No URI given") if !@uri
      @client ||= DRb::DRbObject.new(nil, @uri)
    end

    def run
      raise(ArgumentError, "No target directory given") if !@dir
      pid = Process.fork do
        begin
          server = Imaginator.new(@dir)
          DRb.start_service(@uri, server)
          yield(server) if block_given?
          loop { server.process }
        rescue Errno::EADDRINUSE
        end
      end
      Process.detach(pid)
    end
  end

  def initialize(dir)
    @dir = dir
    @renderer = {}
    @queue = []
    @queue.extend(MonitorMixin)
    @empty = @queue.new_cond
    FileUtils.mkdir_p(@dir, :mode => 0755)
  end

  def add_renderer(type, renderer)
    @renderer[type.to_sym] = renderer
  end

  def enqueue(type, code)
    type = type.to_sym
    renderer = @renderer[type]
    raise(ArgumentError, "Renderer not found") if !renderer
    format = renderer.format
    code = renderer.process(code)
    name = Digest::MD5.hexdigest(code) + '.' + format
    file = File.join(@dir, name)
    if !File.exists?(file)
      @queue.synchronize do
        @queue << [name, type, code]
        @empty.signal
      end
    end
    name
  end

  def result(name)
    file = File.join(@dir, name)
    if !File.exists?(file)
      20.times do
        break if !enqueued?(name)
        sleep 0.5
      end
    end
    raise(RuntimeError, 'Image could not be generated') if !File.exists?(file)
    file
  end

  def process
    name, type, code = @queue.synchronize do
      while @queue.empty? do
        @empty.wait
      end
      @queue.first
    end
    @renderer[type].render(code, File.join(@dir, name)) rescue nil
    @queue.synchronize do
      @queue.shift
    end
  end

  private

  def enqueued?(name)
    @queue.synchronize do
      @queue.any? do |x|
        x[0] == name
      end
    end
  end
end
