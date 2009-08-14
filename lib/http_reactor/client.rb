module HttpReactor #:nodoc:
  class RequestExecutionHandler #:nodoc:
    import org.apache.http.protocol
    import org.apache.http.nio.protocol
    include HttpRequestExecutionHandler
    
    REQUEST_SENT       = "request-sent"
    RESPONSE_RECEIVED  = "response-received"
    
    HTTP_TARGET_PATH = 'http_target_path'
    
    def initialize(request_count, handler_proc)
      @request_count = request_count
      @handler_proc = handler_proc
    end
    
    def initalize_context(context, attachment)
      context.set_attribute(ExecutionContext.HTTP_TARGET_HOST, attachment[:host]);
      context.set_attribute(HTTP_TARGET_PATH, attachment[:path])
    end
    
    def finalize_context(context)
      flag = context.get_attribute(RESPONSE_RECEIVED)
      @request_count.count_down() unless flag
    end
    
    def submit_request(context)
      target_host = context.get_attribute(ExecutionContext.HTTP_TARGET_HOST);
      target_path = context.get_attribute(HTTP_TARGET_PATH)
      flag = context.get_attribute(REQUEST_SENT);
      if flag.nil?
        # Stick some object into the context
        context.set_attribute(REQUEST_SENT, true);

        puts "--------------"
        puts "Sending request to #{target_host}#{target_path}"
        puts "--------------"

        org.apache.http.message.BasicHttpRequest.new("GET", target_path)
      else
        # No new request to submit
      end
    end
     
    def handle_response(response, context)
      @handler_proc.call(response, context)
      
      context.setAttribute(RESPONSE_RECEIVED, true)

      # Signal completion of the request execution
      @request_count.count_down()
    end
  end
  
  class SessionRequestCallback #:nodoc:
    include org.apache.http.nio.reactor.SessionRequestCallback
    
    def initialize(request_count)
      @request_count = request_count
    end

    def cancelled(request)
      puts "Connect request cancelled: #{request.remote_address}"
      @request_count.count_down()
    end

    def completed(request); end

    def failed(request)
      puts "Connect request failed: #{request.remote_address}"
      @request_count.count_down()
    end
    
    def timeout(request)
      puts "Connect request timed out: #{request.remote_address}"
      @request_count.count_down()
    end
  end
  
  class EventLogger #:nodoc:
    import org.apache.http.nio.protocol
    include EventListener
    def connection_open(conn)
      puts "Connection open: #{conn}"
    end
    def connection_timeout(conn)
      puts "Connection timed out: #{conn}"
    end
    def connection_closed(conn)
      puts "Connection closed: #{conn}"
    end
    def fatal_i_o_exception(ex, conn)
      puts "Fatal I/O error: #{ex.message}"
    end
    def fatal_protocol_exception(ex, conn)
      puts "HTTP error: #{ex.message}"
    end
  end
  
  # An HTTP client that uses the Reactor pattern.
  class Client
    import org.apache.http
    import org.apache.http.params
    import org.apache.http.protocol
    import org.apache.http.nio.protocol
    import org.apache.http.impl.nio
    import org.apache.http.impl.nio.reactor
    
    # Create a new HttpReactor client that will request the given URIs.
    #
    # Parameters:
    # * <tt>uris</tt>: An array of URI objects.
    # * <tt>handler_proc</tt>: A Proc that will be called with the response and context
    # * <tt>session_request_callback</tt>: A class that implements the session request
    #   callback interface found in the HttpCore library.
    # * <tt>options: A hash of configuration options. See below.
    # 
    # The options hash may include the following options
    # * <tt>:so_timeout</tt>: (default = 5 seconds)
    # * <tt>:connection_timeout</tt>: The HTTP connection timeout (default = 10 seconds)
    # * <tt>:socket_buffer_size</tt>: The buffer size (defaults to 8Kb)
    # * <tt>:stale_connection_check</tt>: (defaults to false)
    # * <tt>:tcp_nodelay</tt>: (defaults to true)
    # * <tt>:user_agent</tt>: The user agent string to send (defaults to "JRubyHttpReactor")
    # * <tt>:event_listener</tt>: A class that implements the org.apache.http.nio.protocol interface
    def initialize(uris=[], handler_proc=nil, options={})
      handler_proc ||= default_handler_proc
      session_request_callback = SessionRequestCallback
      
      initialize_options(options)
      
      params = build_params(options)
      
      io_reactor = DefaultConnectingIOReactor.new(2, params);
      
      httpproc = BasicHttpProcessor.new;
      httpproc.add_interceptor(RequestContent.new);
      httpproc.add_interceptor(RequestTargetHost.new);
      httpproc.add_interceptor(RequestConnControl.new);
      httpproc.add_interceptor(RequestUserAgent.new);
      httpproc.add_interceptor(RequestExpectContinue.new);
      
      # We are going to use this object to synchronize between the 
      # I/O event and main threads
      request_count = java.util.concurrent.CountDownLatch.new(uris.length);

      handler = BufferingHttpClientHandler.new(
        httpproc,
        RequestExecutionHandler.new(request_count, handler_proc),
        org.apache.http.impl.DefaultConnectionReuseStrategy.new,
        params
      )
      
      handler.event_listener = options[:event_listener].new if options[:event_listener]
      
      io_event_dispatch = DefaultClientIOEventDispatch.new(handler, params)

      Thread.abort_on_exception = true
      t = Thread.new do
        begin
          puts "Executing IO reactor"
          io_reactor.execute(io_event_dispatch)
        rescue java.io.InterruptedIOException => e
          puts "Interrupted"
        rescue java.io.IOException => e
          puts "I/O error in reactor execution thread: #{e.message}"
        end
        puts "Shutdown"
      end
      
      uris.each do |uri|
        io_reactor.connect(
          java.net.InetSocketAddress.new(uri.host, uri.port), 
          nil, 
          {:host => HttpHost.new(uri.host), :path => uri.path},
          session_request_callback.new(request_count)
        )
      end
      
      # Block until all connections signal
      # completion of the request execution
      request_count.await()

      puts "Shutting down I/O reactor"

      io_reactor.shutdown()

      puts "Done"
    end
    
    private
    
    def initialize_options(options)
      options[:so_timeout] ||= 5000
      options[:connection_timeout] ||= 10000
      options[:socket_buffer_size] ||= 8 * 1024
      options[:stale_connection_check] ||= false
      options[:tcp_nodelay] ||= true
      options[:user_agent] ||= "JRubyHttpReactor"
      #options[:event_listener] ||= EventLogger
    end
    
    def build_params(options)
      params = BasicHttpParams.new
      params.set_int_parameter(
        CoreConnectionPNames.SO_TIMEOUT, options[:so_timeout])
      params.set_int_parameter(
        CoreConnectionPNames.CONNECTION_TIMEOUT, options[:connection_timeout])
      params.set_int_parameter(
        CoreConnectionPNames.SOCKET_BUFFER_SIZE, options[:socket_buffer_size])
      params.set_boolean_parameter(
        CoreConnectionPNames.STALE_CONNECTION_CHECK, options[:stale_connection_check])
      params.set_boolean_parameter(
        CoreConnectionPNames.TCP_NODELAY, options[:tcp_nodelay])
      params.set_parameter(
        CoreProtocolPNames.USER_AGENT, options[:user_agent])
      params
    end
    
    def default_handler_proc
      Proc.new { |response, context|
        target_host = context.get_attribute(ExecutionContext.HTTP_TARGET_HOST);
        target_path = context.get_attribute(RequestExecutionHandler::HTTP_TARGET_PATH)

        entity = response.entity
        begin
          content = org.apache.http.util.EntityUtils.toString(entity)

          puts "--------------"
          puts "Response from #{target_host}#{target_path}"
          puts response.status_line
          puts "Document length: #{content.length}"
          puts "--------------"
        rescue java.io.IOException => ex
          puts "I/O error in handle_response: #{ex.message}"
        end 
      }
    end
    
  end
end