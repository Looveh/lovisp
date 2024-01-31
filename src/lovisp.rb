# frozen_string_literal: true

require "readline"

require "./reader"
require "./printer"
require "./env"
require "./core"
require "./types"

class Repl
  def initialize
    @repl_env = Core.new.default_env

    @repl_env.set(:eval, ->(ast) { EVAL(ast, @repl_env) })
    @repl_env.set(:"*ARGV*", LovispList.new(ARGV[1..] || []))
  end

  def eval_ast(ast, env)
    case ast
    when Symbol
      env.get(ast)
    when LovispList
      LovispList.new.tap do |list|
        ast.each { |a| list << EVAL(a, env) }
      end
    when LovispVec
      LovispVec.new.tap do |vec|
        ast.each { |a| vec << EVAL(a, env) }
      end
    when LovispHashMap
      LovispHashMap.new.tap do |map|
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

      if !ast.is_a?(LovispList)
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
          return LovispFn.new(
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
          if !fn.is_a?(LovispFn)
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
            if ast[2].is_a?(LovispList) && ast[2][0] == :"catch*"
              ek = e.is_a?(LovispError) ? e.val : e.message

              return EVAL(ast[2][2], Env.new(env, [ast[2][1]], [ek]))
            else
              raise e
            end
          end
        else
          f, *args = eval_ast(ast, env)

          if f.is_a?(LovispFn)
            ast = f.ast
            env = Env.new(f.env, f.params, args)
          else
            return f.call(*args)
          end
        end
      end
    end
  end

  def quasiquote(ast)
    if ast.is_a?(LovispList)
      if ast.empty?
        ast
      elsif ast[0] == :unquote
        ast[1]
      else
        elt = ast[0]

        if elt.is_a?(LovispList) && elt[0] == :"splice-unquote"
          LovispList.new([:concat, elt[1], quasiquote(LovispList.new(ast[1..]))])
        else
          LovispList.new([:cons, quasiquote(elt), quasiquote(LovispList.new(ast[1..]))])
        end
      end
    elsif ast.is_a?(LovispHashMap) || ast.is_a?(Symbol)
      LovispList.new([:quote, ast])
    else
      ast
    end
  end

  def macro_call?(ast, env)
    ast.is_a?(LovispList) &&
      ast[0].is_a?(Symbol) &&
      env.find(ast[0]).is_a?(LovispFn) &&
      env.get(ast[0]).is_macro
  end

  def macroexpand(ast, env)
    while macro_call?(ast, env)
      fn = env.get(ast[0])
      ast = fn.fn.call(*ast.class.new(ast[1..]))
    end

    ast
  end

  def PRINT(ast)
    Printer.pr_str(ast, print_readably: true)
  end

  def rep(s)
    PRINT(EVAL(READ(s), @repl_env))
  end

  def run_repl
    loop do
      input = Readline.readline("user> ", true)

      if input.nil?
        puts "Exiting"
        break
      end

      begin
        puts rep(input)
      rescue LovispError => e
        puts "Runtime error: #{Printer.pr_str(e.val)}"
      rescue StandardError => e
        puts "Runtime error: #{e.message}"
      end
    end
  end

  def run_file
    rep("(load-file \"#{ARGV[0]}\")")
  end

  def run
    rep(
      <<-TEXT
      (def! not
        (fn* (a)
        (if a false true)))
      TEXT
    )

    rep(
      <<-TEXT
      (def! load-file
        (fn* (f)
          (eval (read-string (str "(do " (slurp f) "\nnil)")))))
      TEXT
    )

    rep(
      <<-TEXT
      (defmacro! cond
        (fn* (& xs)
          (if (> (count xs) 0)
            (list 'if
                  (first xs)
                  (if (> (count xs) 1)
                    (nth xs 1)
                    (throw \"odd number of forms to cond\"))
            (cons 'cond (rest (rest xs)))))))
      TEXT
    )

    if ARGV.empty?
      run_repl
    else
      run_file
    end
  end
end

Repl.new.run
