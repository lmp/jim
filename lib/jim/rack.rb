require 'jim'

module Jim
  # Jim::Rack is a Rack middleware for allowing live bundling and compression
  # of the requirements in your Jimfile without having to rebundle using the command
  # line. You can specify a number of options:
  #
  # :jimfile: Path to your Jimfile (default ./Jimfile)
  # :jimhome: Path to your JIMHOME directory (default ENV['JIMHOME'] or ~/.jim)
  # :bundle_uri: URI to serve the bundled requirements
  class Rack

    def initialize(app, options = {})
      @app = app
      jimfile = Pathname.new(options[:jimfile] || 'Jimfile')
      jimhome = Pathname.new(options[:jimhome] || ENV['JIMHOME'] || '~/.jim').expand_path
      @bundler = Jim::Bundler.new(jimfile, Jim::Index.new(jimhome), options)
      # unset the bundlers bundle dir so it returns a string
      @bundler.bundle_dir = nil
      @bundle_uri = options[:bundle_uri] || '/javascripts/'
    end

    def call(env)
      dup._call(env)
    end

    def _call(env)
      uri = env['PATH_INFO']
      if uri =~ bundle_matcher
        name = $1
        if name =~ compressed_matcher
          run_action(:compress!, name.gsub(compressed_matcher, ''))
        else
          run_action(:bundle!, name)
        end
      else
        @app.call(env)
      end
    end

    private
    def bundle_matcher
      @bundle_matcher ||= /^#{@bundle_uri}([\w\d\-\.]+)\.js$/
    end

    def compressed_matcher
      @compressed_matcher ||= /#{@bundler.options[:compressed_suffix]}$/
    end

    def run_action(action, *args)
      begin
        [200, {
          'Content-Type' => 'text/javascript'
        }, [@bundler.send(action , *args)]]
      rescue => e
        response = <<-EOT
          <p>Jim failed in helping you out. There was an error when trying to run #{action}(#{args}).</p>
          <p>#{e}</p>
          <pre>#{e.backtrace}</pre>
        EOT
        [500, {'Content-Type' => 'text/html'}, [response]]
      end
    end

  end
end
