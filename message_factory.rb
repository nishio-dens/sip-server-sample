class MessageFactory
	def initialize(ip, port)
		@ip = ip
		@port = port 
	end

	def method_not_allowed(element)
		create_response("SIP/2.0 405 Method Not Allowed", element, nil)
	end

	def trying(element)
		create_response("SIP/2.0 100 Trying", element, nil)
	end

	def temporary_unavailable(element)
		create_response("SIP/2.0 480 Temporarily Unavailable", element, nil)
	end

	def invite_message(to_phone_number, address, element, body)
		create_response("INVITE sip:#{to_phone_number}@#{address[:ip]}:#{address[:port]} SIP/2.0", element, body)
	end

	def ringing_message(element)
		create_response("SIP/2.0 180 Ringing", element, nil)
	end

	def ok(element, body)
		create_response("SIP/2.0 200 OK", element, body)
	end

	def ack(to_phone_number, address, element)
		create_response("ACK sip:#{to_phone_number}@#{address[:ip]} SIP/2.0", element, nil)
	end

	private
	def create_response(status_line, header, body)
		response = status_line + "\n"
		response << header.map do |k,v|
			[v].flatten.map do |val|
				k.to_s + ": " + val.to_s + "\n"
			end.to_s
		end.to_s
		response << "\n"
		response << "#{body}\n" unless body == nil
		response.gsub(/\n/,"\r\n")
	end
end
