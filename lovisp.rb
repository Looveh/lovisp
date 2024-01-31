#!/usr/bin/env ruby

require "readline"

# ------------------------------------------------------------------------------
# Types

Fn = Struct.new(
  :ast,
  :params,
  :env,
  :fn,
  :is_macro,
  :meta,
  keyword_init: true
) do
  def call(*args)
    fn.call(*args)
  end

  def copy
    self.class.new(
      ast: ast,
      params: params,
      env: env,
      fn: fn,
      is_macro: is_macro,
      meta: meta
    )
  end

  def to_s
    "#<function>"
  end
end

Atom = Struct.new(:val) do
  def to_s
    "(atom #{val})"
  end
end

Keyword = Struct.new(:val) do
  def to_s
    ":#{val}"
  end
end

class List < Array
  attr_accessor :meta

  def initialize(prev = [])
    super
  end

  def copy
    self.class.new(self)
  end
end

class Vec < Array
  attr_accessor :meta

  def initialize(prev = [])
    super
  end

  def copy
    self.class.new(self)
  end
end

class HashMap < Hash
  attr_accessor :meta

  def initialize(prev = [])
    super

    if prev.is_a?(Array)
      prev.each_slice(2) { |k, v| self[k] = v }
    elsif prev.is_a?(Hash)
      prev.each { |k, v| self[k] = v }
    end
  end

  def copy
    self.class.new(self)
  end
end

class Error < StandardError
  attr_accessor :val

  def initialize(val)
    super
    puts ":Error #{val.class} val"
    @val = val
  end
end

# Yippiekayay
class Proc
  attr_accessor :meta

  def copy
    ->(*args) { call(*args) }
  end
end

# Types
# ------------------------------------------------------------------------------
# Reader

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
      List.new(read_coll)
    when "["
      Vec.new(read_coll)
    when "{"
      HashMap.new(read_coll)
    when "'"
      self.next
      List.new([:quote, read_form])
    when "`"
      self.next
      List.new([:quasiquote, read_form])
    when "~"
      self.next
      List.new([:unquote, read_form])
    when "~@"
      self.next
      List.new([:"splice-unquote", read_form])
    when "^"
      self.next
      meta = read_form
      val = read_form
      List.new([:"with-meta", val, meta])
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
      List.new([:deref, self.next.to_sym])
    elsif token.start_with?(":")
      Keyword.new(token[1..])
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

# Reader
# ------------------------------------------------------------------------------
# Printer

def pr_str(ast, print_readably: false)
  case ast
  when NilClass
    "nil"
  when String
    if print_readably
      "\"" + ast.gsub("\\", "\\\\\\")
                .gsub("\"", "\\\"")
                .gsub("\n", "\\\\n") + "\""
    else
      ast
    end
  when Proc
    "#<function>"
  when List
    vs = ast.map { |v| pr_str(v, print_readably: print_readably) }

    "(#{vs.join(' ')})"
  when Vec
    vs = ast.map { |v| pr_str(v, print_readably: print_readably) }

    "[#{vs.join(' ')}]"
  when HashMap
    kvs = ast.map do |k, v|
      kstr = pr_str(k, print_readably: print_readably)
      vstr = pr_str(v, print_readably: print_readably)
      "#{kstr} #{vstr}"
    end

    "{#{kvs.join(' ')}}"
  when StandardError
    "Error: #{ast}"
  else
    ast.to_s
  end
end

# Printer
# ------------------------------------------------------------------------------
# Builtins

BUILTINS = {
  "*host-language*":
  "ruby",

  "+":
  lambda do |*vals|
    vals.reduce(:+)
  end,

  "-":
  lambda do |*vals|
    vals.reduce(:-)
  end,

  "*":
  lambda do |*vals|
    vals.reduce(:*)
  end,

  "/":
  lambda do |*vals|
    vals.reduce(:/).to_i
  end,

  "=":
  lambda do |*vals|
    vals.each_cons(2).map { |a, b| a == b }.all?
  end,

  "<":
  lambda do |*vals|
    vals.each_cons(2).map { |a, b| a < b }.all?
  end,

  "<=":
  lambda do |*vals|
    vals.each_cons(2).map { |a, b| a <= b }.all?
  end,

  ">":
  lambda do |*vals|
    vals.each_cons(2).map { |a, b| a > b }.all?
  end,

  ">=":
  lambda do |*vals|
    vals.each_cons(2).map { |a, b| a >= b }.all?
  end,

  "prn":
  lambda do |*args|
    puts args.map { |a|
           pr_str(a, print_readably: true)
         }.join(" ")
    nil
  end,

  "pr-str":
  lambda do |*args|
    args.map { |a| pr_str(a, print_readably: true) }.join(" ")
  end,

  "println":
  lambda do |*args|
    ss = args.map { |a| pr_str(a) }.join(" ")

    print(*ss, "\n")
  end,

  "list":
  lambda do |*items|
    List.new(items)
  end,

  "list?":
  lambda do |x|
    x.is_a?(List)
  end,

  "vec":
  lambda do |coll|
    Vec.new(coll)
  end,

  "empty?":
  lambda do |coll|
    coll.empty?
  end,

  "count":
  lambda do |coll|
    coll.nil? ? 0 : coll.length
  end,

  "read-string":
  lambda do |s|
    Reader.read_str(s)
  end,

  "slurp":
  lambda do |path|
    File.read(path)
  end,

  "str":
  lambda do |*args|
    args.map { |a| pr_str(a) }.join
  end,

  "atom":
  lambda do |x|
    Atom.new(val: x)
  end,

  "atom?":
  lambda do |x|
    x.is_a?(Atom)
  end,

  "nth":
  lambda do |coll, n|
    if n >= coll.length
      raise("index out of range")
    else
      coll[n]
    end
  end,

  "first":
  lambda do |coll|
    if coll.nil? || coll.empty?
      nil
    else
      coll[0]
    end
  end,

  "rest":
  lambda do |coll|
    if coll.nil? || coll.empty?
      List.new
    else
      List.new(coll[1..])
    end
  end,

  "deref":
  lambda do |atom|
    if !atom.is_a?(Atom)
      raise "Attempted deref on non-atom"
    end

    atom.val
  end,

  "reset!":
  lambda do |atom, newval|
    if !atom.is_a?(Atom)
      raise "Attempted reset! on non-atom"
    end

    atom.val = newval
  end,

  "swap!":
  lambda do |atom, fn, *params|
    if !atom.is_a?(Atom)
      raise "Attempted swap! on non-atom"
    end

    if fn.is_a?(Fn)
      fn = fn.fn
    end

    atom.val = fn.call(atom.val, *params)
  end,

  "cons":
  lambda do |head, tail|
    List.new(tail).unshift(head)
  end,

  "concat":
  lambda do |*args|
    if args.empty?
      List.new
    else
      List.new.tap do |this|
        args.each do |that|
          this.concat(that)
        end
      end
    end
  end,

  "throw":
  lambda do |err|
    raise Error.new(err)
  end,

  "apply":
  lambda do |fn, *args|
    fn = fn.fn if fn.is_a?(Fn)
    fn.call(*args.flatten(1))
  end,

  "map":
  lambda do |fn, coll|
    fn = fn.fn if fn.is_a?(Fn)
    List.new(coll.map { |a| fn.call(a) })
  end,

  "nil?":
  lambda do |x|
    x.nil?
  end,

  "true?":
  lambda do |x|
    x.is_a?(TrueClass)
  end,

  "false?":
  lambda do |x|
    x.is_a?(FalseClass)
  end,

  "symbol?":
  lambda do |x|
    x.is_a?(Symbol)
  end,

  "symbol":
  lambda do |x|
    if !x.is_a?(String)
      raise "Must be string"
    end

    x.to_sym
  end,

  "keyword":
  lambda do |x|
    if x.is_a?(Keyword)
      x
    elsif x.is_a?(String)
      Keyword.new(x)
    else
      raise "Must be string or keyword"
    end
  end,

  "keyword?":
  lambda do |x|
    x.is_a?(Keyword)
  end,

  "vector":
  lambda do |*args|
    Vec.new.tap do |vec|
      args.each do |a|
        vec << a
      end
    end
  end,

  "vector?":
  lambda do |x|
    x.is_a?(Vec)
  end,

  "sequential?":
  lambda do |x|
    x.is_a?(Vec) || x.is_a?(List)
  end,

  "hash-map":
  lambda do |*args|
    if args.length.odd?
      raise "Odd number of arguments"
    end

    HashMap.new.tap do |m|
      args.each_slice(2) do |k, v|
        m[k] = v
      end
    end
  end,

  "map?":
  lambda do |x|
    x.is_a?(HashMap)
  end,

  "assoc":
  lambda do |coll, *kvs|
    if !coll.is_a?(HashMap)
      raise "Not a hash-map"
    elsif kvs.length.odd?
      raise "Odd number of arguments"
    end

    HashMap.new(coll).tap do |new_coll|
      kvs.each_slice(2) do |k, v|
        new_coll[k] = v
      end
    end
  end,

  "dissoc":
  lambda do |coll, *kvs|
    HashMap.new(coll).tap do |new_coll|
      kvs.each do |k|
        new_coll.delete(k)
      end
    end
  end,

  "get":
  lambda do |coll, k|
    coll&.key?(k) ? coll[k] : nil
  end,

  "contains?":
  lambda do |coll, k|
    coll.key?(k)
  end,

  "keys":
  lambda do |coll|
    List.new(coll.keys)
  end,

  "vals":
  lambda do |coll|
    List.new(coll.values)
  end,

  "time-ms":
  lambda do
    (Time.now.to_f * 1000).to_i
  end,

  "meta":
  lambda do |x|
    x.meta
  end,

  "with-meta":
  lambda do |x, m|
    x.copy.tap { |y| y.meta = m }
  end,

  "fn?":
  lambda do |x|
    x.is_a?(Fn) || x.is_a?(Proc)
  end,

  "string?":
  lambda do |x|
    x.is_a?(String)
  end,

  "number?":
  lambda do |x|
    x.is_a?(Numeric)
  end,

  "seq":
  lambda do |x|
    if x.nil? || x.empty?
      nil
    elsif x.is_a?(List)
      x
    elsif x.is_a?(Vec)
      List.new(x)
    elsif x.is_a?(String)
      List.new(x.split(""))
    else
      raise "Unknown type"
    end
  end,

  "conj":
  lambda do |coll, *args|
    if coll.is_a?(List)
      List.new([*args.reverse, *coll])
    elsif coll.is_a?(Vec)
      Vec.new([*coll, *args])
    else
      raise "Unknown coll type"
    end
  end,

  "readline":
  lambda do |prompt|
    Readline.readline(prompt, true)
  end,

  "eval":
  lambda do |ast|
    EVAL(ast, ROOT_ENV)
  end,

  "*ARGV*":
  List.new(ARGV[1..] || []),

  "load-file":
  lambda do |path|
    load_file(path)
  end
}.freeze

# Builtins
# ------------------------------------------------------------------------------
# Env

class Env
  class NotFound < StandardError
    def initialize(k)
      super("'#{k}' not found")
    end
  end

  attr_reader :outer

  def initialize(outer = nil, binds = [], exprs = [])
    @outer = outer
    @data = {}

    binds.each_with_index do |k, i|
      if k == :&
        @data[binds[i + 1]] = List.new(exprs[i..])
        break
      end

      @data[k] = exprs[i]
    end
  end

  def set(k, v)
    @data[k] = v
  end

  def set_root(k, v)
    outer = @outer

    while outer&.outer
      outer = outer.outer
    end

    if outer
      outer.set(k, v)
    else
      set(k, v)
    end
  end

  def find(k)
    if @data.key?(k)
      @data[k]
    elsif !@outer
      NotFound.new(k)
    else
      @outer.find(k)
    end
  end

  def get(k)
    find(k).tap do |v|
      if v.is_a?(NotFound)
        raise v
      end
    end
  end
end

# Env
# ------------------------------------------------------------------------------
# Eval

ROOT_ENV = Env.new.tap do |env|
  BUILTINS.each do |k, v|
    env.set(k, v)
  end
end

def eval_ast(ast, env)
  case ast
  when Symbol
    env.get(ast)
  when List
    List.new.tap do |list|
      ast.each { |a| list << EVAL(a, env) }
    end
  when Vec
    Vec.new.tap do |vec|
      ast.each { |a| vec << EVAL(a, env) }
    end
  when HashMap
    HashMap.new.tap do |map|
      ast.each { |k, v| map[EVAL(k, env)] = EVAL(v, env) }
    end
  else
    ast
  end
end

def READ(s)
  Reader.read_str(s)
end

def EVAL(ast, env)
  loop do
    ast = macroexpand(ast, env)

    if !ast.is_a?(List)
      return eval_ast(ast, env)
    elsif ast.empty?
      return ast
    else
      case ast[0]
      when :def!
        return env.set_root(ast[1], EVAL(ast[2], env))
      when :"let*"
        env = Env.new(env)

        ast[1].each_slice(2) do |k, kast|
          env.set(k, EVAL(kast, env))
        end

        ast = ast[2]
      when :do
        ast[1...-1].each do |kast|
          EVAL(kast, env)
        end

        ast = ast.last
      when :if
        ast = EVAL(ast[1], env) ? ast[2] : ast[3]
      when :"fn*"
        return Fn.new(
          is_macro: false,
          ast: ast[2],
          params: ast[1],
          env: env,
          fn: lambda { |*args|
            EVAL(ast[2], Env.new(env, ast[1], args))
          }
        )
      when :quote
        return ast[1]
      when :quasiquote
        ast = quasiquote(ast[1])
      when :quasiquoteexpand
        return quasiquote(ast[1])
      when :defmacro!
        fn = EVAL(ast[2], env)
        if !fn.is_a?(Fn)
          raise "macro did not evaluate to fn"
        end

        fn.is_macro = true
        return env.set_root(ast[1], fn)
      when :macroexpand
        return macroexpand(ast[1], env)
      when :"try*"
        begin
          return EVAL(ast[1], env)
        rescue StandardError => e
          if ast[2].is_a?(List) && ast[2][0] == :"catch*"
            ek = e.is_a?(Error) ? e.val : e.message

            return EVAL(ast[2][2], Env.new(env, [ast[2][1]], [ek]))
          else
            raise e
          end
        end
      else
        f, *args = eval_ast(ast, env)

        if f.is_a?(Fn)
          ast = f.ast
          env = Env.new(f.env, f.params, args)
        else
          return f.call(*args)
        end
      end
    end
  end
end

def PRINT(ast)
  pr_str(ast, print_readably: true)
end

def quasiquote(ast)
  if ast.is_a?(List)
    if ast.empty?
      ast
    elsif ast[0] == :unquote
      ast[1]
    else
      elt = ast[0]

      if elt.is_a?(List) && elt[0] == :"splice-unquote"
        List.new([:concat, elt[1],
                  quasiquote(List.new(ast[1..]))])
      else
        List.new([:cons, quasiquote(elt),
                  quasiquote(List.new(ast[1..]))])
      end
    end
  elsif ast.is_a?(HashMap) || ast.is_a?(Symbol)
    List.new([:quote, ast])
  else
    ast
  end
end

def macro_call?(ast, env)
  ast.is_a?(List) &&
    ast[0].is_a?(Symbol) &&
    env.find(ast[0]).is_a?(Fn) &&
    env.get(ast[0]).is_macro
end

def macroexpand(ast, env)
  while macro_call?(ast, env)
    fn = env.get(ast[0])
    ast = fn.fn.call(*ast.class.new(ast[1..]))
  end

  ast
end

def READ_EVAL_PRINT(s)
  PRINT(EVAL(READ(s), ROOT_ENV))
end

def run_repl
  loop do
    input = Readline.readline("user> ", true)

    if input.nil?
      break
    end

    begin
      puts READ_EVAL_PRINT(input)
    rescue Error => e
      puts "Runtime error: #{pr_str(e.val)}"
    rescue StandardError => e
      puts "Runtime error: #{e.message}"
    end
  end
end

def load_file(path)
  content = File.read(path)

  READ_EVAL_PRINT("(do #{content})")
end

# Eval
# ------------------------------------------------------------------------------
# Main

def main
  load_file(File.join(File.dirname(__FILE__), "./stdlib.lp"))

  if ARGV.empty?
    run_repl
  else
    load_file(ARGV[0])
  end
end

if __FILE__ == $PROGRAM_NAME
  main
end
