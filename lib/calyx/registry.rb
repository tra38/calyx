module Calyx
  class Registry
    attr_reader :rules, :transforms, :modifiers

    # Construct an empty registry.
    def initialize
      @rules = {}
      @transforms = {}
      @modifiers = Modifiers.new
    end

    # Hook for defining rules without explicitly calling the `#rule` method.
    #
    # @param name [Symbol]
    # @param productions [Array]
    def method_missing(name, *arguments)
      rule(name, *arguments)
    end

    # Attaches a modifier module to this instance.
    #
    # @param module_name [Module]
    def modifier(name)
      modifiers.extend(name)
    end

    # Registers a paired mapping regex.
    #
    # @param name [Symbol]
    # @param pairs [Hash<Regex,String>]
    def mapping(name, pairs)
      transforms[name.to_sym] = construct_mapping(pairs)
    end

    # Registers the given block as a string filter.
    #
    # @param name [Symbol]
    # @block block with a single string argument returning a modified string.
    def filter(name, callable=nil, &block)
      if block_given?
        transforms[name.to_sym] = block
      else
        transforms[name.to_sym] = callable
      end
    end

    # Registers a new grammar rule.
    #
    # @param name [Symbol]
    # @param productions [Array]
    def rule(name, *productions)
      rules[name.to_sym] = construct_rule(productions)
    end

    # Expands the given rule symbol to its production.
    #
    # @param symbol [Symbol]
    def expand(symbol)
      rules[symbol] || context[symbol]
    end

    # Applies the given modifier function to the given value to transform it.
    #
    # @param name [Symbol]
    # @param value [String]
    # @return [String]
    def transform(name, value)
      if transforms.key?(name)
        transforms[name].call(value)
      else
        modifiers.transform(name, value)
      end
    end

    # Expands a memoized rule symbol by evaluating it and storing the result
    # for later.
    #
    # @param symbol [Symbol]
    def memoize_expansion(symbol)
      memos[symbol] ||= expand(symbol).evaluate
    end

    # Merges the given registry instance with the target registry.
    #
    # This is only needed at compile time, so that child classes can easily
    # inherit the set of rules decared by their parent.
    #
    # @param registry [Calyx::Registry]
    def combine(registry)
      @rules = rules.merge(registry.rules)
    end

    # Evaluates the grammar defined in this registry, combining it with rules
    # from the passed in context.
    #
    # Produces a syntax tree of nested list nodes.
    #
    # @param start_symbol [Symbol]
    # @param rules_map [Hash]
    # @return [Array]
    def evaluate(start_symbol=:start, rules_map={})
      reset_evaluation_context

      rules_map.each do |key, value|
        if rules.key?(key.to_sym)
          raise Error::DuplicateRule.new(key)
        end

        context[key.to_sym] = if value.is_a?(Array)
          Production::Choices.parse(value, self)
        else
          Production::Concat.parse(value.to_s, self)
        end
      end

      expansion = expand(start_symbol)

      if expansion.respond_to?(:evaluate)
        [start_symbol, expansion.evaluate]
      else
        raise Errors::MissingRule.new(start_symbol)
      end
    end

    private

    attr_reader :memos, :context

    def reset_evaluation_context
      @context = {}
      @memos = {}
    end

    def construct_mapping(pairs)
      mapper = -> (input) {
        match, target = pairs.detect { |match, target| input =~ match }
        input.gsub(match, target)
      }
    end

    def construct_rule(productions)
      if productions.first.is_a?(Hash)
        Production::WeightedChoices.parse(productions.first.to_a, self)
      elsif productions.first.is_a?(Enumerable)
        Production::WeightedChoices.parse(productions, self)
      else
        Production::Choices.parse(productions, self)
      end
    end
  end
end
