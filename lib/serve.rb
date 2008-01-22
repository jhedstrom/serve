require 'serve/version'
require 'webrick/extensions'

module Serve #:nodoc:
  class FileTypeHandler < WEBrick::HTTPServlet::AbstractServlet #:nodoc:
    
    def self.extension(extension)
      WEBrick::HTTPServlet::FileHandler.add_handler(extension, self)
    end
    
    def initialize(server, name)
      super
      @script_filename = name
    end
    
    def process(req, res)
      data = open(@script_filename){|io| io.read }
      res['content-type'] = content_type
      res.body = parse(data)
    end
    
    def do_GET(req, res)
      begin
        process(req, res)
      rescue StandardError => ex
        raise
      rescue Exception => ex
        @logger.error(ex)
        raise WEBrick::HTTPStatus::InternalServerError, ex.message
      end
    end
    
    alias do_POST do_GET
    
    protected
    
      def content_type
        'text/html'
      end
      
      def parse(string)
        string.dup
      end
      
  end
  
  class TextileHandler < FileTypeHandler #:nodoc:
    extension 'textile'
    
    def parse(string)
      require 'redcloth'
      "<html><body>#{ RedCloth.new(string).to_html }</body></html>"
    end
  end
  
  class MarkdownHandler < FileTypeHandler #:nodoc:
    extension 'markdown'
    
    def parse(string)
      require 'bluecloth'
      "<html><body>#{ BlueCloth.new(string).to_html }</body></html>"
    end
  end
  
  class HamlHandler < FileTypeHandler #:nodoc:
    extension 'haml'
    
    def parse(string)
      require 'haml'
      engine = Haml::Engine.new(string,
        :attr_wrapper => '"',
        :filename => @script_filename
      )
      layout = find_layout(@script_filename)
      if layout
        lines = IO.read(layout)
        scope = Context.new(Dir.pwd, @script_filename, engine.options.dup)
        rendered = engine.render(scope)
        layout_engine = Haml::Engine.new(lines, engine.options.dup)
        layout_engine.render(scope) do
          rendered
        end
      else
        engine.render
      end
    end
    
    def find_layout(filename)
      root = Dir.pwd
      path = filename[root.size..-1]
      layout = nil
      begin
        path = File.dirname(path)
        l = File.join(root, path, '_layout.haml')
        layout = l if File.file?(l)
      end until layout or path == "/"
      layout
    end
    
    class Context
      def initialize(root, script_filename, engine_options)
        @root, @script_filename, @engine_options = root, script_filename, engine_options
      end
      
      def render(options)
        partial = options.delete(:partial)
        case
        when partial
          render_partial(partial)
        else
          raise "render options not supported #{options.inspect}"
        end
      end
      
      def render_partial(partial)
        path = File.dirname(@script_filename)
        if partial =~ %r{^/}
          partial = partial[1..-1]
          path = @root
        end
        filename = File.join(path, "_" + partial + ".haml")
        if File.file?(filename)
          lines = IO.read(filename)
          engine = Haml::Engine.new(lines, @engine_options)
          engine.render(self)
        else
          raise "File does not exist #{filename.inspect}"
        end
      end
    end
  end
  
  class SassHandler < FileTypeHandler #:nodoc:
    extension 'sass'
    
    def parse(string)
      require 'sass'
      engine = Sass::Engine.new(string,
        :style => :expanded,
        :filename => @script_filename
      )
      engine.render 
    end
    
    def content_type
      'text/css'
    end
  end
  
  class EmailHandler < FileTypeHandler #:nodoc:
    extension 'email'
    
    def parse(string)
      title = "E-mail"
      title = $1 + " #{title}" if string =~ /^Subject:\s*(\S.*?)$/im
      head, body = string.split("\n\n", 2)
      output = []
      output << "<html><head><title>#{title}</title></head>"
      output << '<body style="font-family: Arial; line-height: 1.2em; font-size: 90%; margin: 0; padding: 0">'
      output << '<div id="head" style="background-color: #E9F2FA; padding: 1em">'
      head.each do |line|
        key, value = line.split(":", 2).map { |a| a.strip }
        output << "<div><strong>#{key}:</strong> #{value}</div>"
      end
      output << '</div><pre id="body" style="font-size: 110%; padding: 1em">'
      output << body
      output << '</pre></body></html>'
      output.join("\n")
    end
  end
  
  class RedirectHandler < FileTypeHandler  #:nodoc:
    extension 'redirect'
    
    def process(req, res)
      data = super
      res['location'] = data.strip
      res.body = ''
      raise WEBrick::HTTPStatus::Found
    end
  end
  
  class Server < WEBrick::HTTPServer #:nodoc:
  end
  
end