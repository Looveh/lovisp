require "readline"

require "./env"
require "./printer"
require "./reader"
require "./types"

class Core
  def initialize
    @ns = {
      :"*host-language*" => "ruby",
      :+ => ->(*args) { args.reduce(:+) },
      :- => ->(*args) { args.reduce(:-) },
      :* => ->(*args) { args.reduce(:*) },
      :/ => ->(*args) { args.reduce(:/).to_i },
      :"=" => ->(a, b) { a == b },
      :< => ->(a, b) { a < b },
      :<= => ->(a, b) { a <= b },
      :> => ->(a, b) { a > b },
      :>= => ->(a, b) { a >= b },
      :prn => lambda do |*args|
        puts args.map { |a| Printer.pr_str(a, print_readably: true) }.join(" ")
        nil
      end,
      :"pr-str" => lambda do |*args|
        args.map { |a| Printer.pr_str(a, print_readably: true) }.join(" ")
      end,
      :println => lambda do |*args|
        ss = args.map { |a| Printer.pr_str(a, print_readably: false) }.join(" ")
        print(*ss, "\n")
      end,
      :list => ->(*args) { LovispList.new(args) },
      :list? => ->(a) { a.is_a?(LovispList) },
      :vec => ->(args) { LovispVec.new(args) },
      :empty? => ->(a) { a.empty? },
      :count => ->(a) { a.nil? ? 0 : a.length },
      :"read-string" => ->(s) { Reader.read_str(s) },
      :slurp => ->(path) { File.read(path) },
      :str => ->(*args) { args.map { |a| Printer.pr_str(a) }.join },
      :atom => ->(a) { LovispAtom.new(val: a) },
      :atom? => ->(a) { a.is_a?(LovispAtom) },
      :nth => lambda do |coll, n|
        if n >= coll.length
          raise("index out of range")
        else
          coll[n]
        end
      end,
      :first => lambda do |coll|
        if coll.nil? || coll.empty?
          nil
        else
          coll[0]
        end
      end,
      :rest => lambda do |coll|
        if coll.nil? || coll.empty?
          LovispList.new
        else
          LovispList.new(coll[1..])
        end
      end,
      :deref => lambda do |a|
        if !a.is_a?(LovispAtom)
          raise "Attempted deref on non-atom"
        end

        a.val
      end,
      :reset! => lambda do |a, v|
        if !a.is_a?(LovispAtom)
          raise "Attempted reset! on non-atom"
        end

        a.val = v
        v
      end,
      :swap! => lambda do |a, *args|
        if !a.is_a?(LovispAtom)
          raise "Attempted swap! on non-atom"
        end

        fn, *params = args
        if fn.is_a?(LovispFn)
          fn = fn.fn
        end
        a.val = fn.call(a.val, *params)
        a.val
      end,
      :cons => ->(head, tail) { LovispList.new(tail).unshift(head) },
      :concat => lambda do |*args|
        if args.empty?
          LovispList.new
        else
          LovispList.new.tap do |this|
            args.each do |that|
              this.concat(that)
            end
          end
        end
      end,
      :throw => ->(err) { raise LovispError.new(err) },
      :apply => lambda do |fn, *args|
        if fn.is_a?(LovispFn)
          fn = fn.fn
        end

        fn.call(*args.flatten(1))
      end,
      :map => lambda do |fn, coll|
        if fn.is_a?(LovispFn)
          fn = fn.fn
        end

        LovispList.new(coll.map { |a| fn.call(a) })
      end,
      :nil? => ->(a) { a.nil? },
      :true? => ->(a) { a.is_a?(TrueClass) },
      :false? => ->(a) { a.is_a?(FalseClass) },
      :symbol? => ->(a) { a.is_a?(Symbol) },
      :symbol => lambda do |s|
        if !s.is_a?(String)
          raise "Must be string"
        end

        s.to_sym
      end,
      :keyword => lambda do |a|
        if a.is_a?(LovispKeyword)
          a
        elsif a.is_a?(String)
          LovispKeyword.new(a)
        else
          raise "Must be string or keyword"
        end
      end,
      :keyword? => ->(a) { a.is_a?(LovispKeyword) },
      :vector => lambda do |*args|
        LovispVec.new.tap do |vec|
          args.each do |a|
            vec << a
          end
        end
      end,
      :vector? => ->(a) { a.is_a?(LovispVec) },
      :sequential? => ->(a) { a.is_a?(LovispVec) || a.is_a?(LovispList) },
      :"hash-map" => lambda do |*args|
        if args.length.odd?
          raise "Odd number of arguments"
        end

        LovispHashMap.new.tap do |m|
          args.each_slice(2) do |k, v|
            m[k] = v
          end
        end
      end,
      :map? => ->(a) { a.is_a?(LovispHashMap) },
      :assoc => lambda do |m, *args|
        if !m.is_a?(LovispHashMap)
          raise "Not a hash-map"
        elsif args.length.odd?
          raise "Odd number of arguments"
        end

        LovispHashMap.new(m).tap do |new_m|
          args.each_slice(2) do |k, v|
            new_m[k] = v
          end
        end
      end,
      :dissoc => lambda do |m, *ks|
        LovispHashMap.new(m).tap do |new_m|
          ks.each do |k|
            new_m.delete(k)
          end
        end
      end,
      :get => ->(m, k) { m&.key?(k) ? m[k] : nil },
      :contains? => ->(m, k) { m.key?(k) },
      :keys => ->(m) { LovispList.new(m.keys) },
      :vals => ->(m) { LovispList.new(m.values) },
      :"time-ms" => -> { (Time.now.to_f * 1000).to_i },
      :meta => ->(a) { a.meta },
      :"with-meta" => ->(a, m) { a.copy.tap { |b| b.meta = m } },
      :fn? => ->(a) { a.is_a?(LovispFn) || a.is_a?(Proc) },
      :string? => ->(a) { a.is_a?(String) },
      :number? => ->(a) { a.is_a?(Numeric) },
      :seq => lambda do |a|
        if a.nil? || a.empty?
          nil
        elsif a.is_a?(LovispList)
          a
        elsif a.is_a?(LovispVec)
          LovispList.new(a)
        elsif a.is_a?(String)
          LovispList.new(a.split(""))
        else
          raise "Unknown type"
        end
      end,
      :conj => lambda do |coll, *args|
        if coll.is_a?(LovispList)
          LovispList.new([*args.reverse, *coll])
        elsif coll.is_a?(LovispVec)
          LovispVec.new([*coll, *args])
        else
          raise "Unknown coll type"
        end
      end,
      :readline => ->(prompt) { Readline.readline(prompt, true) }
    }
  end

  def default_env
    Env.new.tap do |env|
      @ns.each do |k, v|
        env.set(k, v)
      end
    end
  end
end
