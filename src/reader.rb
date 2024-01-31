class Reader
  def initialize(tokens)
    @tokens = tokens
    @cursor = 0
  end

  def next
    token = @tokens[@cursor]
    @cursor += 1
    token
  end

  def peek
    @tokens[@cursor]
  end

  def read_form
    while peek&.start_with?(";")
      self.next
    end

    case peek
    when "("
      LovispList.new(read_coll)
    when "["
      LovispVec.new(read_coll)
    when "{"
      LovispHashMap.new(read_coll)
    when "'"
      self.next
      LovispList.new([:quote, read_form])
    when "`"
      self.next
      LovispList.new([:quasiquote, read_form])
    when "~"
      self.next
      LovispList.new([:unquote, read_form])
    when "~@"
      self.next
      LovispList.new([:"splice-unquote", read_form])
    when "^"
      self.next
      meta = read_form
      val = read_form
      LovispList.new([:"with-meta", val, meta])
    else
      read_atom
    end
  end

  def read_coll
    [].tap do |coll|
      ender = {
        "(" => ")",
        "[" => "]",
        "{" => "}"
      }[self.next] # Pop leading bracket

      loop do
        token = peek

        if token.nil?
          raise "EOF"
        elsif token == ender
          break
        else
          coll << read_form
        end
      end

      self.next # Pop trailing bracket
    end
  end

  def read_atom
    token = self.next

    if token.nil? || token == "nil"
      nil
    elsif token == "true"
      true
    elsif token == "false"
      false
    elsif token.start_with?("@")
      LovispList.new([:deref, self.next.to_sym])
    elsif token.start_with?(":")
      LovispKeyword.new(token[1..])
    elsif token.to_i.to_s == token
      token.to_i
    elsif token.start_with?("\"")
      if token == "\"" || !token.end_with?("\"")
        raise "EOF"
      end

      s = ""

      i = 1
      while i < token.length - 1
        if token[i] == "\\"
          if i == token.length - 2
            raise "EOF"
          end

          case token[i + 1]
          when "\\"
            s << "\\"
          when "\""
            s << "\""
          when "n"
            s << "\n"
          else
            raise "EOF"
          end
          i += 1
        else
          s << token[i]
        end
        i += 1
      end

      s
      # token[1...-1].gsub("\\\"", "\"").gsub("\\n", "\n").gsub("\\\\", "\\")
    else
      token.to_sym
    end
  end

  def self.tokenize(s)
    re = /[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)/

    s.scan(re).map(&:first).reject(&:empty?)
  end

  def self.read_str(s)
    Reader.new(tokenize(s)).read_form
  end
end
