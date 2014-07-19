module Functional

  ProtocolError = Class.new(StandardError)

  def DefineProtocol(protocol, &block)
    protocol = protocol.to_sym
    protocol_info = ProtocolCheck.class_variable_get(:@@info)[protocol]

    return protocol_info unless block_given?

    if block_given? && ! protocol_info.nil?
      raise ProtocolError.new(":#{protocol} has already been defined")
    end

    info = {
      methods: {},
      class_methods: {},
      constants: []
    }

    proxy = Class.new do
      def initialize(info)
        @info = info
      end
      def method(name, arity = nil)
        arity = arity.to_i unless arity.nil?
        @info[:methods][name.to_sym] = arity
      end
      def class_method(name, arity = nil)
        arity = arity.to_i unless arity.nil?
        @info[:class_methods][name.to_sym] = arity
      end
      def attr_reader(name)
        method(name, 0)
      end
      def attr_writer(name)
        method("#{name}=".to_sym, 1)
      end
      def attr_accessor(name)
        attr_reader(name)
        attr_writer(name)
      end
      def class_attr_reader(name)
        class_method(name, 0)
      end
      def class_attr_writer(name)
        class_method("#{name}=".to_sym, 1)
      end
      def class_attr_accessor(name)
        class_attr_reader(name)
        class_attr_writer(name)
      end
      def constant(name)
        @info[:constants] << name.to_sym
      end
    end

    proxy.new(info).instance_eval(&block)
    ProtocolCheck.class_variable_get(:@@info)[protocol] = info
  end
  module_function :DefineProtocol

  module ProtocolCheck

    @@info = {}

    def Satisfy?(target, *protocols)
      protocols.drop_while { |protocol|
        ProtocolCheck.satisfies?(target, protocol.to_sym)
      }.empty?
    end

    def Satisfy!(target, *protocols)
      Satisfy?(target, *protocols) or
        ProtocolCheck.error(target, 'does not', protocols)
      target
    end

    def Protocol?(*protocols)
      ProtocolCheck.undefined(*protocols).empty?
    end

    def Protocol!(*protocols)
      (undefined = ProtocolCheck.undefined(*protocols)).empty? or
        raise ProtocolError.new("The following protocols are undefined: :#{undefined.join('; :')}.")
    end

    private

    def self.check_arity?(target, method, expected)
      arity = target.method(method).arity
      expected.nil? || arity == -1 || expected == arity
    rescue
      return false
    end

    def self.check_constant?(target, constant)
      target = target.class unless target.is_a?(Module)
      target.class.const_defined?(constant)
    end

    def self.satisfies?(target, protocol)
      target.class # trigger lazy loading
      clazz = target.is_a?(Module) ? target : target.class
      info = @@info[protocol]
      return false if info.nil?

      results = info[:constants].drop_while do |constant|
        check_constant?(target, constant)
      end
      return false unless results.empty?

      results = info[:methods].drop_while do |method, arity|
        check_arity?(target, method, arity)
      end
      return false unless results.empty?

      results = info[:class_methods].drop_while do |method, arity|
        check_arity?(clazz, method, arity)
      end

      results.empty?
    end

    def self.undefined(*protocols)
      protocols.drop_while do |protocol|
        @@info.has_key? protocol.to_sym
      end
    end

    def self.error(target, message, protocols)
      target = target.class unless target.is_a?(Module)
      raise ProtocolError,
        "Value (#{target.class}) '#{target}' #{message} behave as all of: :#{protocols.join('; :')}."
      target
    end
  end
end
