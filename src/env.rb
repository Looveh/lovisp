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
        @data[binds[i + 1]] = LovispList.new(exprs[i..])
        break
      end

      @data[k] = exprs[i]
    end
  end

  def to_s
    "Env<@data=#{@data}, @outer=#{@outer}>"
  end

  def set(k, v)
    @data[k] = v
    v
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
    v = find(k)

    raise v if v.is_a?(NotFound)

    v
  end
end
