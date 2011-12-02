# -*- coding: utf-8 -*-
require 'socket'
require 'logger'

require 'message_factory'
#TODO:
#受け取ったメッセージのHeader順番を保持しなければならない [SHOULD]

class SipServer
  def initialize(ip, port = 5060)
    @ip = ip
    @port = port
    @via_server_info = "SIP/2.0/UDP #{@ip}:#{@port};branch=z9hG4bK-0"
    @log = Logger.new(STDOUT)
    @address_book = {}
    @trying_list = {}
    @message = MessageFactory.new(ip, port)
  end

  def register(element)
    #register sip address
    if element['Contact']
      address = split_address(element['Contact'])
      @address_book[ address[:phone_number] ] = { 
        :ip => address[:ip],
        :port => address[:port],
        :option => address[:option],
        :id => element['Call-ID'],
        :agent => element['User-Agent'],
        :allow => element['Allow'],
        :expires => element['Expires']
      }
      @log.info("Regist New Address(Number: #{address[:phone_number]}) -- #{@address_book[address[:phone_number]].inspect}")
      return true
    end
    return false
  end

  def invite(element, body, socket)
    begin
      from = split_address(element['From'])
      to = split_address(element['To'])
      @log.info("start Calling from #{from[:phone_number]} to #{to[:phone_number]}.")
      elem = add_via(element)
      if @address_book[to[:phone_number]]
        invite_message = @message.invite_message(to[:phone_number], @address_book[to[:phone_number]],elem, body)
        to_address = @address_book[ to[:phone_number] ]
        socket.send(invite_message,0,to_address[:ip], to_address[:port])
        @log.info("Send Invite Message To #{to_address[:ip]}:#{to_address[:port]}")
        @log.info("Message:\n#{invite_message}")
        #Fromからtag情報を取得
        tag = get_tag(from[:after_option])
        if tag
          @trying_list[tag] = from[:phone_number]
          @log.info("Add Trying List : #{tag}-#{@trying_list[tag].to_s}")
        end
      else
        @log.info("Number #{to[:phone_number]} Not Found.")
      end
    rescue => e
      p e
      e.backtrace
    end
  end

  def ringing(element, body, socket)
    from = split_address(element['From'])
    begin
      tag = get_tag(from[:after_option])
      trying_number = @trying_list[tag]
      if trying_number
        address = @address_book[trying_number]
        elem = remove_via(element)
        ring = @message.ringing_message(elem)
        socket.send(ring,0, address[:ip], address[:port])
        @log.info("Ringing #{address[:ip]}:#{address[:port]}")
      end
    rescue => e
      p e
      e.backtrace
    end
  end

  def ok(element, body, socket)
    if element['CSeq'] =~ /\d INVITE/
      #invite OK
      trying_number = get_trying_number(element)
      if trying_number
        address = @address_book[trying_number]
        elem = remove_via(element)
        data = @message.ok(elem, body)
        socket.send(data, 0, address[:ip], address[:port])
        @log.info("Invite OK (#{address[:ip]}:#{address[:port]})")
      end
    end
  end

  def start
    server = UDPSocket.new
    server.bind(@ip, @port)
    @log.info("Start SIP Server. [IP = #{@ip}, Port = #{@port}]")
    while true
      socklist = IO::select([server])
      if socklist
        socklist[0].each do |socket|
          begin
            text, sender = socket.recvfrom_nonblock(8192)
            type, element, body = split_request_message(text.gsub(/\r/,''))

            @log.info("Request from #{sender[3]}")
            @log.info("Type: #{type}")
            #@log.info("Element: #{element.inspect}")
            #@log.info("Body: #{body}")

            request = type.split(/\s/) unless type == nil
            if type && type.size >= 2
              if request[2] == "SIP/2.0"
                #Request Message
                response = nil
                if type != nil and request[2] == "SIP/2.0"
                  case request[0]
                  when "REGISTER"
                    if register(element)
                      response = @message.ok(element,nil)
                    end
                  when "INVITE"
                    invite(element, body, socket)
                    response = @message.trying(element)
                  when "ACK"
                    #nothing
                  else
                    response = @message.method_not_allowed(element)
                  end
                end
                if response
                  socket.send(response, 0, sender[3], sender[1])
                  #@log.info("Send Response: #{response}")
                  @log.info("Send Response to #{sender[3]}:#{sender[1]}")
                end  
              else request[0] = "SIP/2.0"
                #Response Message
                case request[1].to_s
                when "180" #RINGING
                  ringing(element, body, socket)
                when "200" #OK
                  ok(element, body, socket)
                end
              end
            end
          rescue => e
            p e.inspect
            p e.backtrace
          end
        end
      end
    end
  end

  private
  def get_tag(text)
    text =~ /tag[\s]*=[\s]*([\w]+)/
      return $1
  end

  def split_address(contact)
    address = {}
    if contact =~ /([\w\\\"]*)\s*<sip:([\w]+)@(\d+\.\d+\.\d+\.\d+):*(\d*);*(.*)>;*(.*)/
      address = { :username => $1, :phone_number => $2, :ip => $3, :port => $4, :option => $5, :after_option => $6 }
    end
    address
  end

  #return type, header_element, body
  def split_request_message(message)
    header_and_body = message.split(/\n\n/)
    if header_and_body[0]
      message_type = header_and_body[0].split(/\n/)[0]
      header_element = header_to_hash(header_and_body[0])
    end
    return message_type, header_element, header_and_body[1]
  end

  def header_to_hash(body)
    result = {}
    body.each_line do |line|
      if line =~ /([A-Za-z\-_]*):\s(.*)/
        if result[$1]
          result[$1] = [result[$1],$2].flatten
        else
          result[$1] = $2
        end
      end
    end
    return result
  end

  def get_trying_number(element)
    from = split_address(element['From'])
    tag = get_tag(from[:after_option])
    @trying_list[tag]
  end

  def add_via(element)
    if [element['Via']].flatten.size > 1
      element['Via'] << @via_server_info
    else
      element['Via'] = [@via_server_info, element['Via']]
    end
    element
  end

  def remove_via(element)
    if [element['Via']].flatten.size > 1
      element['Via'].delete(@via_server_info)
    end
    element
  end
end

if ARGV.length < 1
  puts "please type your ip address"
else
  SipServer.new(ARGV[0]).start
end
