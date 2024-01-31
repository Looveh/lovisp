class Printer
  def self.pr_str(ast, print_readably: false)
    case ast
    when NilClass
      "nil"
    when TrueClass
      "true"
    when FalseClass
      "false"
    when String
      if print_readably
        "\"" + ast.gsub("\\", "\\\\\\").gsub("\"", "\\\"").gsub("\n", "\\\\n") + "\""
      else
        ast
      end
    when Integer
      ast.to_s
    when Float
      ast.to_s
    when Symbol
      ast.to_s
    when LovispAtom
      "(atom #{ast.val})"
    when LovispFn
      "#<function>"
    when Proc
      "#<function>"
    when LovispList
      vs = ast.map { |v| pr_str(v, print_readably: print_readably) }

      "(#{vs.join(' ')})"
    when LovispVec
      vs = ast.map { |v| pr_str(v, print_readably: print_readably) }

      "[#{vs.join(' ')}]"
    when LovispHashMap
      kvs = ast.map do |k, v|
        "#{pr_str(k, print_readably: print_readably)} #{pr_str(v, print_readably: print_readably)}"
      end

      "{#{kvs.join(' ')}}"
    when LovispKeyword
      ast.to_s
    when StandardError
      "Error: #{ast}"
    else
      raise "Unknown type #{ast.class}: #{ast}"
    end
  end
end
