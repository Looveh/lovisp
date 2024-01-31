LovispFn = Struct.new(:ast, :params, :env, :fn, :is_macro, :meta, keyword_init: true) do
  def call(*args)
    fn.call(*args)
  end

  def copy
    self.class.new(ast: ast, params: params, env: env, fn: fn, is_macro: is_macro, meta: meta)
  end
end

LovispAtom = Struct.new(:val)

# yolo
class Proc
  attr_accessor :meta

  def copy
    ->(*args) { call(*args) }
  end
end

class LovispList < Array
  attr_accessor :meta

  def initialize(prev = [])
    super
  end

  def copy
    self.class.new(self)
  end
end

class LovispVec < Array
  attr_accessor :meta

  def initialize(prev = [])
    super
  end

  def copy
    self.class.new(self)
  end
end

class LovispHashMap < Hash
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

class LovispKeyword
  attr_accessor :val

  def initialize(val)
    @val = val
  end

  def to_s
    ":#{@val}"
  end

  def hash
    @val.hash
  end

  def eql?(other)
    other.is_a?(self.class) && @val == other.val
  end

  def ==(other)
    other.is_a?(self.class) && @val == other.val
  end
end

class LovispError < StandardError
  attr_accessor :val

  def initialize(val)
    super
    puts ":LovispError #{val.class} val"
    @val = val
  end
end
