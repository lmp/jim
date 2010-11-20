require 'optparse'
require 'readline'

module Jim

  # CLI handles the command line interface for the `jim` binary.
  # The layout is fairly simple. Options are parsed using optparse.rb and
  # the different public methods represent 1-1 the commands provided by the bin.
  class CLI

    attr_accessor :jimfile, :jimhome, :force, :stdout

    # create a new instance with the args passed from the command line i.e. ARGV
    def initialize(args)
      @output = ""
      # set the default jimhome
      self.jimhome = Pathname.new(ENV['JIMHOME'] || '~/.jim').expand_path
      # parse the options
      self.jimfile = Pathname.new('Jimfile')
      @args = parse_options(args)
      ## try to run based on args
    end

    # method called by the bin directly after initialization.
    def run(reraise = false)
      command = @args.shift
      if command && respond_to?(command)
        self.send(command, *@args)
      elsif command.nil? || command.strip == ''
        cheat
      else
        @output << "No action found for #{command}. Run -h for help."
      end
      @output
    rescue ArgumentError => e
      @output << "#{e.message} for #{command}"
      raise e if reraise
    rescue Jim::FileExists => e
      @output << "#{e.message} already exists, bailing. Use --force if you're sure"
      raise e if reraise
    rescue => e
      @output << e.message + " (#{e.class})"
      raise e if reraise
    end

    # list the possible commands to the logger
    def commands
      logger.info "Usage: jim [options] [command] [args]\n"
      logger.info "Commands:"
      logger.info template('commands')
    end

    # list the possible commands without detailed descriptions
    def cheat
      logger.info "Usage: jim [options] [command] [args]\n"
      logger.info "Commands:"
      logger.info [*template('commands')].grep(/^\w/).join
      logger.info "run commands for details"
    end
    alias :help :cheat

    # initialize the current dir with a new Jimfile
    def init(dir = nil)
      dir = Pathname.new(dir || '')
      jimfile_path = dir + 'Jimfile'
      if jimfile_path.readable? && !force
        raise Jim::FileExists.new(jimfile_path)
      else
        File.open(jimfile_path, 'w') do |f|
          f << template('jimfile')
        end
        logger.info "wrote Jimfile to #{jimfile_path}"
      end
    end

    # install the file/project `url` into `jimhome`
    def install(url, name = false, version = false)
      Jim::Installer.new(url, jimhome, :force => force, :name => name, :version => version).install
    end

    # bundle the files specified in Jimfile into `to`
    def bundle(to = nil)
      to = STDOUT if stdout
      io = bundler.bundle!(to)
      logger.info "Wrote #{File.size(io.path) / 1024}kb" if io.respond_to? :path
    end

    # compress the files specified in Jimfile into `to`
    def compress(to = nil)
      to = STDOUT if stdout
      io = bundler.compress!(to)
      logger.info "Wrote #{File.size(io.path) / 1024}kb" if io.respond_to? :path
    end

    # copy/vendor all the files specified in Jimfile to `dir`
    def vendor(dir = nil)
      bundler.vendor!(dir, force)
    end

    # list the only the _installed_ projects and versions.
    # Match names against `search` if supplied.
    def list(search = nil)
      logger.info "Getting list of installed files in\n#{installed_index.directories.join(':')}"
      logger.info "Searching for '#{search}'" if search
      list = installed_index.list(search)
      logger.info "Installed:"
      print_version_list(list)
    end
    alias :installed :list

    # list all available projects and versions including those in the local path, or
    # paths specified in a Jimfile.
    # Match names against `search` if supplied.
    def available(search = nil)
      logger.info "Getting list of all available files in\n#{index.directories.join("\n")}"
      logger.info "Searching for '#{search}'" if search
      list = index.list(search)
      logger.info "Available:"
      print_version_list(list)
    end

    # Iterates over matching files and prompts for removal
    def remove(name, version = nil)
      logger.info "Looking for files matching #{name} #{version}"
      files = installed_index.find_all(name, version)
      if files.length > 0
        logger.info "Found #{files.length} matching files"
        removed = 0
        files.each do |filename|
          response = Readline.readline("Remove #{filename}? (y/n)\n")
          if response.strip =~ /y/i
            logger.info "Removing #{filename}"
            filename.delete
            removed += 1
          else
            logger.info "Skipping #{filename}"
          end
        end
        logger.info "Removed #{removed} files."
      else
        logger.info "No installed files matched."
      end
    end
    alias :uninstall :remove

    # list the files and their resolved paths specified in the Jimfile
    def resolve
      resolved = bundler.resolve!
      logger.info "Files:"
      resolved.each do |r|
        logger.info r.join(" | ")
      end
      resolved
    end

    # vendor to dir, then bundle and compress the Jimfile contents
    def pack(dir = nil)
      logger.info "packing the Jimfile for this project"
      vendor(dir)
      bundle
      compress
    end

    private
    def parse_options(runtime_args)
      OptionParser.new("", 24, '  ') do |opts|
        opts.banner = "Usage: jim [options] [command] [args]"

        opts.separator ""
        opts.separator "jim options:"

        opts.on("--jimhome path/to/home", "set the install path/JIMHOME dir (default ~/.jim)") {|h|
          self.jimhome = Pathname.new(h)
        }

        opts.on("-j", "--jimfile path/to/jimfile", "load specific Jimfile at path (default ./Jimfile)") { |j|
          self.jimfile = Pathname.new(j)
        }

        opts.on("-f", "--force", "force file creation/overwrite") {|f|
          self.force = true
        }

        opts.on("-d", "--debug", "set log level to debug") {|d|
          logger.level = Logger::DEBUG
        }

        opts.on("-o", "--stdout", "write output of commands (like bundle and compress to STDOUT)") {|o|
          logger.level = Logger::ERROR
          self.stdout = true
        }

        opts.on("-v", "--version", "print version") {|d|
          puts "jim #{Jim::VERSION}"
          exit
        }


        opts.on_tail("-h", "--help", "Show this message. Run jim commands for list of commands.") do
          puts opts.help
          exit
        end

      end.parse! runtime_args
    rescue OptionParser::MissingArgument => e
      logger.warn "#{e}, run -h for options"
      exit
    end

    def index
      @index ||= Jim::Index.new(install_dir, Dir.pwd)
    end

    def installed_index
      @installed_index ||= Jim::Index.new(install_dir)
    end

    def bundler
      @bundler ||= Jim::Bundler.new(jimfile, index)
    end

    def install_dir
      jimhome + 'lib'
    end

    def template(path)
      (Pathname.new(__FILE__).dirname + 'templates' + path).read
    end

    def logger
      Jim.logger
    end

    def print_version_list(list)
      list.each do |file, versions|
        logger.info "#{file} (#{VersionSorter.rsort(versions.collect {|v| v[0] }).join(', ')})"
      end
    end

  end
end
